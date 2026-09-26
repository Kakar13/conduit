# conduit

An iOS SSH client built for one thing: open your phone, drop straight into a
live remote server stream, run your commands, get out. Designed for managing
cloud servers (AWS EC2 and friends) from an iPhone.

- **No clutter.** A single dark, Metal-accelerated terminal. The only chrome
  is a status dot.
- **Live status in the Dynamic Island.** The bridge state (connected,
  connecting, reconnecting, offline) is a Live Activity — visible on any
  app, on the Lock Screen, and one tap takes you to the server switcher.
- **A resilient data bridge.** Built on Apple's Network.framework with
  multipath handover, so the session rides through Wi-Fi ⇄ cellular
  transitions. When the transport truly dies, it re-establishes itself with
  capped exponential backoff — keystrokes typed mid-blip are buffered and
  flushed on reconnect. Add `tmux new -A -s main` as the profile's reattach
  command and you land back in the exact same remote session.
- **Keys locked in hardware.** The P-256 private key is created inside the
  iPhone's Secure Enclave and never leaves it; the enclave only ever emits
  signatures. Face ID guards key use.
- **The missing keys.** A compact row above the keyboard: `esc`, a latching
  `ctrl`, `tab`, hold-to-repeat arrows, `home`, `end`, `pgup`, `pgdn`, and
  `| ~ ` -`.

## Stack

| Layer | Choice |
| --- | --- |
| UI | SwiftUI (iOS 26, `@Observable`, Liquid Glass), UIKit where it counts |
| Live status | ActivityKit Live Activity (Dynamic Island + Lock Screen) via a Widget extension |
| Terminal | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Metal renderer) |
| SSH | [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) |
| Transport | Network.framework via [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services), `multipathServiceType = .handover`, TCP keepalive, `NWPathMonitor` |
| Keys | CryptoKit `SecureEnclave.P256` + LocalAuthentication (Face ID) |
| Persistence | SwiftData (server profiles, known hosts) |
| Language | Swift 6, strict concurrency, actors |

## Build

Requires Xcode 26+ on macOS. The Xcode project is generated with
[XcodeGen](https://github.com/yonsm/XcodeGen):

```sh
brew install xcodegen
xcodegen
open conduit.xcodeproj
```

Then:

1. Select the `conduit` scheme and your signing team.
2. Enable the **Multipath** capability for the App ID in the Developer
   portal (the entitlement is already in `Conduit.entitlements`). Without it
   the app still works — handover just falls back to reconnects.
3. Run on a device (the Secure Enclave is not available in the Simulator).

## First run

1. conduit mints a P-256 key inside the Secure Enclave and shows you the
   public key.
2. Add it to `~/.ssh/authorized_keys` on your server (for EC2: EC2 Instance
   Connect, the console, or `user-data`).
3. Enter host + username, tap **Connect**. Face ID unlocks the key.
4. Next launch drops you straight into the terminal, already connecting.

## How the resilience works

```
 ┌────────────┐   NWConnection (multipath handover, TCP keepalive)
 │  SwiftTerm │ ◄──────────────────────────────────────────────┐
 └─────┬──────┘                                                │
       │ feed / send                                           │
 ┌─────▼──────┐    ┌───────────────┐    ┌────────────────────┐ │
 │ SSHSession │ ─► │ NIOSSHHandler │ ─► │ NIOTSConnectionCh. │ │
 │  (actor)   │ ◄─ │  (swift-nio-  │ ◄─ │ (Network.framework)│ │
 └─────┬──────┘    │     ssh)      │    └────────────────────┘ │
       │           └───────────────┘                           │
       │  NWPathMonitor: path lost → kill socket now;          │
       │  path back → retry immediately. closeFuture →         │
       │  reconnect w/ backoff (0.5s→15s, 20 attempts).        │
       ▼                                                       │
 Secure Enclave P-256 (sign only) ── Face ID gate ─────────────┘
```

- **Handover**: iOS moves the flow between Wi-Fi and cellular without a
  reconnect where the path allows it (requires the Multipath entitlement).
- **Detection**: `NWPathMonitor` kills a dead socket immediately instead of
  waiting minutes for TCP timeouts; keepalive catches black-holed links.
- **Recovery**: reconnect replays handshake + auth + pty + shell and flushes
  buffered input. The terminal buffer is never cleared.
- **Remote persistence**: the shell on the far end still dies with TCP. For
  true session persistence set the profile's reattach command to
  `tmux new -A -s main` (or `screen -xRR`) — reconnects then resume the
  exact remote session.

## Security notes

- Private key material is non-exportable by construction (Secure Enclave).
- Face ID is enforced at the app level before the key is loaded, with a
  5-minute reuse window so automatic reconnects don't prompt. To require
  biometry on *every* signature instead, add `.biometryAny` to the
  access-control flags in `SecureEnclaveKeyStore.createKey` (reconnects will
  then prompt).
- Host keys use trust-on-first-use with SwiftData persistence; a changed key
  is always refused and surfaced as a possible MITM.
- No analytics, no telemetry, no servers of our own.

## License

See [LICENSE](LICENSE).
