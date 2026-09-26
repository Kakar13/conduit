import Foundation
import NIOCore
import NIOSSH
import NIOTransportServices
import Network

/// Errors surfaced by the SSH layer.
enum SSHSessionError: LocalizedError {
    case noActiveProfile
    case unexpectedChannelType
    case publicKeyAuthNotAvailable
    case hostKeyRejected

    var errorDescription: String? {
        switch self {
        case .noActiveProfile:
            return "No server selected."
        case .unexpectedChannelType:
            return "The server refused to open a shell channel."
        case .publicKeyAuthNotAvailable:
            return "The server does not accept public-key authentication."
        case .hostKeyRejected:
            return "The server's host key was not trusted."
        }
    }
}

/// The resilient data bridge.
///
/// One `SSHSession` owns the whole lifecycle: a Network.framework TCP
/// connection with Wi-Fi ⇄ cellular handover enabled, the SSH handshake on
/// top of it, and the interactive shell channel. When the transport dies —
/// a tunnel, an elevator, a tower handoff the multipath layer couldn't
/// absorb — the session re-establishes itself with capped exponential
/// backoff, keeping the terminal buffer untouched. Keystrokes typed while
/// the bridge is down are buffered (up to 8 KB) and flushed on reconnect.
///
/// A monotonically increasing `generation` tags every connection attempt, so
/// close events from a deliberately torn-down transport can never trigger a
/// spurious reconnect.
actor SSHSession {
    // MARK: - Public types

    enum State: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case disconnected
    }

    enum Event: Sendable {
        case stateChanged(State)
        case hostKeyChallenge(HostKeyChallenge)
        case hostKeyAlert(HostKeyAlert)
    }

    // MARK: - Streams (each consumed exactly once, by the UI layer)

    let events: AsyncStream<Event>
    let output: AsyncStream<Data>
    private let eventContinuation: AsyncStream<Event>.Continuation
    private let outputContinuation: AsyncStream<Data>.Continuation

    // MARK: - Dependencies

    private let keyStore: SecureEnclaveKeyStore
    private let hostKeyVerifier: KnownHostStore

    // MARK: - Transport state

    private var group: NIOTSEventLoopGroup?
    private var channel: Channel?
    private var childChannel: Channel?
    private var pathMonitor: NWPathMonitor?
    private var generation = 0

    // MARK: - Session state

    private var profile: ServerEndpoint?
    private var cols = 80
    private var rows = 24
    private var intentionalDisconnect = false
    private var reconnectTask: Task<Void, Never>?
    private var retryRequested = false
    private var pendingInput: [UInt8] = []
    private var pendingHostKeyResponse: CheckedContinuation<Bool, Never>?

    private static let maxReconnectAttempts = 20
    private static let maxPendingInputBytes = 8192

    private(set) var state: State = .idle {
        didSet { eventContinuation.yield(.stateChanged(state)) }
    }

    init(keyStore: SecureEnclaveKeyStore, hostKeyVerifier: KnownHostStore) {
        let (events, eventContinuation) = AsyncStream.makeStream(of: Event.self)
        let (output, outputContinuation) = AsyncStream.makeStream(of: Data.self)
        self.events = events
        self.eventContinuation = eventContinuation
        self.output = output
        self.outputContinuation = outputContinuation
        self.keyStore = keyStore
        self.hostKeyVerifier = hostKeyVerifier
    }

    // MARK: - Connect / disconnect

    func connect(to profile: ServerEndpoint) async throws {
        generation += 1
        intentionalDisconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        await teardownTransport()
        self.profile = profile
        state = .connecting
        startPathMonitoring()
        do {
            try await establishConnection()
        } catch {
            state = .disconnected
            throw error
        }
    }

    func disconnect() async {
        generation += 1
        intentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        stopPathMonitoring()
        await teardownTransport()
        state = .idle
    }

    // MARK: - Input

    /// Sends user keystrokes to the remote shell. While the bridge is down
    /// the bytes are buffered and flushed on reconnect, so typing through a
    /// network blip loses nothing.
    func send(_ bytes: [UInt8]) {
        guard let child = childChannel, state == .connected else {
            pendingInput.append(contentsOf: bytes)
            if pendingInput.count > Self.maxPendingInputBytes {
                pendingInput.removeFirst(pendingInput.count - Self.maxPendingInputBytes)
            }
            return
        }
        Self.write(bytes, to: child)
    }

    /// The terminal changed size; propagate to the remote pty.
    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        guard let child = childChannel, state == .connected else { return }
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        child.triggerUserOutboundEvent(request, promise: nil)
    }

    // MARK: - Host key verification

    func respondToHostKeyChallenge(accept: Bool) {
        pendingHostKeyResponse?.resume(returning: accept)
        pendingHostKeyResponse = nil
    }

    func resetKnownHost(host: String, port: Int) {
        Task { await hostKeyVerifier.remove(host: host, port: port) }
    }

    private func verifyHostKey(host: String, port: Int, publicKey: NIOSSHPublicKey) async -> Bool {
        let openSSH = String(openSSHPublicKey: publicKey)
        let keyType = openSSH.split(separator: " ").first.map(String.init) ?? "unknown"
        let fingerprint = SSHWireFormat.fingerprint(openSSHKey: openSSH)

        switch await hostKeyVerifier.lookup(host: host, port: port, presentedKey: openSSH) {
        case .match:
            return true

        case .mismatch(let expectedFingerprint):
            eventContinuation.yield(.hostKeyAlert(HostKeyAlert(
                host: host,
                port: port,
                expectedFingerprint: expectedFingerprint,
                presentedFingerprint: fingerprint
            )))
            return false

        case .unknown:
            eventContinuation.yield(.hostKeyChallenge(HostKeyChallenge(
                host: host,
                port: port,
                keyType: keyType,
                fingerprint: fingerprint,
                openSSHKey: openSSH
            )))
            let accepted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                pendingHostKeyResponse = continuation
            }
            if accepted {
                await hostKeyVerifier.store(
                    host: host,
                    port: port,
                    keyType: keyType,
                    openSSHKey: openSSH,
                    fingerprint: fingerprint
                )
            }
            return accepted
        }
    }

    // MARK: - Connection establishment

    private func establishConnection() async throws {
        guard let profile else { throw SSHSessionError.noActiveProfile }

        // Tear down any half-dead transport (including its event loop group)
        // before starting fresh.
        await teardownTransport()

        let group = NIOTSEventLoopGroup(loopCount: 1)
        let enclaveKey = try keyStore.privateKey()
        let nioKey = NIOSSHPrivateKey(secureEnclaveP256Key: enclaveKey)

        let userAuth = ConduitUserAuthDelegate(username: profile.username, privateKey: nioKey)
        let serverAuth = KnownHostsServerDelegate { [weak self] hostKey in
            await self?.verifyHostKey(host: profile.host, port: profile.port, publicKey: hostKey) ?? false
        }

        do {
            let channel = try await SSHTransport.connect(
                host: profile.host,
                port: profile.port,
                userAuthDelegate: userAuth,
                serverAuthDelegate: serverAuth,
                group: group
            )

            let child = try await Self.openShellChannel(
                on: channel,
                cols: cols,
                rows: rows,
                onOutput: { [outputContinuation] data in
                    outputContinuation.yield(data)
                }
            )

            self.group = group
            self.channel = channel
            self.childChannel = child

            let currentGeneration = generation
            channel.closeFuture.whenComplete { [weak self] _ in
                Task { await self?.handleTransportClosed(generation: currentGeneration) }
            }
            child.closeFuture.whenComplete { [weak self] _ in
                Task { await self?.handleShellClosed(generation: currentGeneration) }
            }

            state = .connected
            flushPendingInput()

            // Re-attach to a multiplexer (e.g. tmux) when configured, so a
            // reconnect lands back in the same remote session.
            if !profile.reattachCommand.isEmpty {
                send(Array((profile.reattachCommand + "\n").utf8))
            }
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private static func openShellChannel(
        on channel: Channel,
        cols: Int,
        rows: Int,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws -> Channel {
        let sshHandler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()

        let child: Channel = try await withCheckedThrowingContinuation { continuation in
            let promise = channel.eventLoop.makePromise(of: Channel.self)
            promise.futureResult.whenComplete { continuation.resume(with: $0) }
            sshHandler.createChannel(promise) { childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(SSHSessionError.unexpectedChannelType)
                }
                return childChannel.eventLoop.makeCompletedFuture {
                    let sync = childChannel.pipeline.syncOperations
                    try sync.addHandler(ShellChannelHandler(onOutput: onOutput))
                }
            }
        }

        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: false,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        try await child.triggerUserOutboundEvent(pty).get()
        try await child.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true)).get()
        return child
    }

    private static func write(_ bytes: [UInt8], to child: Channel) {
        var buffer = child.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        child.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)), promise: nil)
    }

    private func flushPendingInput() {
        guard let child = childChannel, !pendingInput.isEmpty else { return }
        let bytes = pendingInput
        pendingInput.removeAll(keepingCapacity: true)
        Self.write(bytes, to: child)
    }

    // MARK: - Resilience

    /// Fires when the parent connection dies. Starts the reconnect loop
    /// unless the event belongs to a stale generation or the user asked for
    /// the disconnect.
    private func handleTransportClosed(generation: Int) {
        guard generation == self.generation, !intentionalDisconnect else { return }
        guard state == .connected || state == .connecting else { return }
        scheduleReconnect()
    }

    /// Fires when the shell channel closes. If the transport is still alive
    /// the remote shell simply exited (e.g. the user typed `exit`) — that is
    /// an end of session, not a network failure, so we do not reconnect.
    private func handleShellClosed(generation: Int) {
        guard generation == self.generation, !intentionalDisconnect else { return }
        guard state == .connected else { return }
        if channel?.isActive == true {
            state = .disconnected
        } else {
            handleTransportClosed(generation: generation)
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 1...Self.maxReconnectAttempts {
                guard !Task.isCancelled else { return }
                await self.setState(.reconnecting(attempt: attempt))
                let shouldStop = await self.sleepWithEarlyRetry(Self.backoff(attempt: attempt))
                guard !Task.isCancelled, !shouldStop else { return }
                do {
                    try await self.establishConnection()
                    await self.clearReconnectTask()
                    return
                } catch {
                    continue
                }
            }
            await self.reconnectExhausted()
        }
    }

    /// Capped exponential backoff: 0.5s, 1s, 2s, … max 15s.
    private static func backoff(attempt: Int) -> Double {
        min(0.5 * pow(2.0, Double(attempt - 1)), 15.0)
    }

    /// Sleeps in 200 ms slices so a returning network path (or a user-initiated
    /// retry) can cut the backoff short without cancelling the task.
    ///
    /// - Returns: true if the reconnect loop should abort entirely.
    private func sleepWithEarlyRetry(_ seconds: Double) async -> Bool {
        var waited = 0.0
        while waited < seconds {
            if Task.isCancelled || intentionalDisconnect { return true }
            if retryRequested {
                retryRequested = false
                return false
            }
            try? await Task.sleep(for: .milliseconds(200))
            waited += 0.2
        }
        return Task.isCancelled || intentionalDisconnect
    }

    private func setState(_ newState: State) {
        state = newState
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    private func reconnectExhausted() {
        reconnectTask = nil
        state = .disconnected
    }

    // MARK: - Path monitoring

    /// Watches interface availability. When every path drops we kill the
    /// socket immediately instead of waiting minutes for a TCP timeout, and
    /// when a path returns we retry at once rather than sitting in backoff.
    private func startPathMonitoring() {
        stopPathMonitoring()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handlePathUpdate(satisfied: path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    private func stopPathMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePathUpdate(satisfied: Bool) {
        if !satisfied {
            channel?.close(promise: nil)
        } else if case .reconnecting = state {
            retryRequested = true
        }
    }

    // MARK: - Teardown

    private func closeChannels() async {
        let child = childChannel
        let parent = channel
        childChannel = nil
        channel = nil
        if let child { try? await child.close().get() }
        if let parent { try? await parent.close().get() }
    }

    private func teardownTransport() async {
        await closeChannels()
        let oldGroup = group
        group = nil
        if let oldGroup { try? await oldGroup.shutdownGracefully() }
    }
}
