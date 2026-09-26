import Foundation
import NIOCore
import NIOSSH
import NIOTransportServices
import Network

/// Builds the Network.framework transport that carries the SSH connection.
///
/// The connection runs over `NWConnection` (via NIO Transport Services) with
/// the multipath handover service enabled: iOS keeps the flow alive across
/// Wi-Fi ⇄ cellular transitions wherever the network path allows it, and
/// TCP keepalive detects genuinely dead sockets quickly so the session's
/// reconnect logic can kick in.
enum SSHTransport {
    static func connect(
        host: String,
        port: Int,
        userAuthDelegate: ConduitUserAuthDelegate,
        serverAuthDelegate: KnownHostsServerDelegate,
        group: NIOTSEventLoopGroup
    ) async throws -> Channel {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 20
        tcpOptions.keepaliveInterval = 10
        tcpOptions.keepaliveCount = 3
        tcpOptions.noDelay = true

        // The client configuration is deliberately created inside the
        // channel initializer: `SSHClientConfiguration` is not Sendable, so
        // it must not cross actor or @Sendable-closure boundaries. Only the
        // (Sendable) delegates are captured.
        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .connectTimeout(.seconds(20))
            .tcpOptions(tcpOptions)
            .withMultipath(.handover)
            .configureNWParameters { parameters in
                parameters.multipathServiceType = .handover
            }
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let configuration = SSHClientConfiguration(
                        userAuthDelegate: userAuthDelegate,
                        serverAuthDelegate: serverAuthDelegate
                    )
                    let ssh = NIOSSHHandler(
                        role: .client(configuration),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    try channel.pipeline.syncOperations.addHandler(ssh)
                }
            }

        return try await bootstrap.connect(host: host, port: port).get()
    }
}
