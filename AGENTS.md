# AGENTS.md

## What this is

`conduit` — an iOS SSH client for any remote SSH host (cloud VMs, bare
metal, home labs; e.g. AWS EC2). One dark full-bleed terminal, a resilient
Network.framework transport, Secure Enclave keys guarded by Face ID, and a
compact accessory key row.

## Build & test

- There is **no checked-in `.xcodeproj`** — it is generated:
  `brew install xcodegen && xcodegen` (spec: `project.yml`).
- Requires Xcode 26+, iOS 26 deployment target, Swift 6 language mode with
  strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`).
- Secure Enclave requires a **physical device**; the Simulator cannot create
  enclave keys.
- The Multipath entitlement (`Conduit/Conduit.entitlements`) must be enabled
  on the App ID for Wi-Fi ⇄ cellular handover; without it the app still
  works via reconnects.
- No test targets yet. Verify changes by building in Xcode
  (`xcodegen && xcodebuild -scheme conduit -destination 'generic/platform=iOS'`).

## Dependencies (SwiftPM, declared in `project.yml`)

- `migueldeicaza/SwiftTerm` (branch `main`) — terminal emulator. Public API
  used: `TerminalView`, `terminalDelegate`, `feed(byteArray:)`,
  `send(_:)`/`sendKey*`, `controlModifier`, `inputAccessoryView`,
  `setUseMetal(_:)`, `updateUiClosed()`.
- `apple/swift-nio-ssh` (from 0.11.0) — SSH protocol. Used:
  `NIOSSHHandler`, `SSHClientConfiguration`, `NIOSSHPrivateKey(secureEnclaveP256Key:)`,
  `String(openSSHPublicKey:)`, `SSHChannelRequestEvent` pty/shell/window-change.
- `apple/swift-nio-transport-services` (from 1.23.0) — NIO over
  Network.framework. Used: `NIOTSEventLoopGroup`, `NIOTSConnectionBootstrap`
  with `withMultipath(.handover)` + `configureNWParameters`.

## Architecture

- `Conduit/App` — `ConduitApp` (SwiftUI `App` + SwiftData container),
  `AppModel` (`@MainActor @Observable`: biometric gate → `session.connect`,
  consumes `session.events`), `RootView` (onboarding vs terminal,
  auto-connect to last used server, `conduit://servers` deep link),
  `LiveActivityController` (mirrors session state into the Dynamic Island /
  Lock Screen Live Activity).
- `ConduitStatusWidget` — Widget extension (separate target) rendering the
  Live Activity. `Shared/ConduitActivityAttributes.swift` is compiled into
  both targets and is the only contract between them.
- `Conduit/SSH` — the engine. `SSHSession` is an **actor** and the single
  owner of transport state; it exposes `events`/`output` `AsyncStream`s
  (each consumed exactly once). Reconnects use a `generation` counter so
  stale close events can't trigger spurious reconnects, capped exponential
  backoff, and an early-retry flag driven by `NWPathMonitor`.
  `Transport/SSHTransport` builds the multipath `NWConnection` bootstrap.
  `Auth/` holds the user-auth delegate (offers the enclave key once), the
  TOFU server-auth delegate, and `KnownHostStore` (@MainActor, SwiftData).
  `Shell/ShellChannelHandler` forwards `SSHChannelData` bytes to the
  terminal. `SSHWireFormat` encodes OpenSSH public keys + SHA256
  fingerprints.
- `Conduit/Security` — `SecureEnclaveKeyStore` (CryptoKit enclave keys;
  `dataRepresentation` blob kept in the keychain) and
  `BiometricAuthenticator` (Face ID with a 5-minute reuse window so
  auto-reconnects don't prompt).
- `Conduit/Terminal` — `TerminalViewRepresentable` (+ `Coordinator`
  implementing `TerminalViewDelegate`), `AccessoryKeyBar` (UIInputView,
  esc/ctrl latch/tab/arrows/etc.), `TerminalScreen` (full-bleed surface,
  host-key alerts, consumes `session.output`).
- `Conduit/UI` — `StatusPill` (only chrome), `OnboardingView`,
  `ServerListView`/`AddServerView`, `ServerFormFields`.
- `Conduit/Models` — `ServerProfile`, `KnownHost` (SwiftData `@Model`),
  `ServerEndpoint` (Sendable snapshot of a profile; the only thing handed to
  the SSH actor — SwiftData models never cross actor boundaries),
  `HostKeyChallenge`, `HostKeyAlert`.

## Conventions

- Swift 6 strict concurrency: the SSH layer is actor-isolated; NIO handlers
  are `@unchecked Sendable` with `@Sendable` callbacks; UI is `@MainActor`.
- `@Observable` classes, not `ObservableObject`. SwiftData for persistence.
- NIO futures are bridged with `.get()` / continuations — no blocking waits.
- Keep the UI minimal on purpose: no new chrome without a strong reason.
- When adding SPM dependencies or build settings, edit `project.yml` (not a
  generated project) and re-run `xcodegen`.
