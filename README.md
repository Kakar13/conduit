# conduit

An iOS SSH client built for one thing: open your phone, drop straight into a
live remote server stream, run your commands, get out. Works with **any host
that speaks SSH** — cloud VMs (EC2, Droplets, Hetzner, Lightsail), bare
metal, home labs, Raspberry Pis, containers — anything with an `sshd` and
your public key in `authorized_keys`.

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

## Protocol & standards

conduit is built on published standards, end to end:

| Standard | What conduit uses it for |
| --- | --- |
| **RFC 4251** | SSH protocol architecture (transport / userauth / connection layers). |
| **RFC 4253** | Transport layer: key exchange, encryption & integrity, server host-key verification. |
| **RFC 4252** | `publickey` user authentication — the auth challenge is signed inside the Secure Enclave. |
| **RFC 4254** | Connection protocol: `session` channel, `pty-req` (§6.2, `xterm-256color`), `shell` (§6.5), `window-change` (§6.7) on resize. |
| **RFC 5656** | `ecdsa-sha2-nistp256` keys and signatures (P-256 / ECDSA, also FIPS 186-5). |
| **RFC 7435** | Trust-on-first-use for server host keys (pin first, refuse changes). |
| **RFC 6824** | Multipath TCP — the transport behind Wi-Fi ⇄ cellular handover. |
| **RFC 793 / RFC 6298** | TCP itself, and why conduit doesn't wait on it: retransmission timeouts can take minutes, so dead sockets are killed proactively. |
| **RFC 1122 §4.2.3.6** | TCP keepalive probes (20 s idle, 10 s interval, 3 probes). |
| **ECMA-48 / xterm** | Terminal control sequences, emulated by SwiftTerm. |

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

conduit's onboarding is a ladder — every rung works on **any host with an
sshd**, from an EC2 instance to a Raspberry Pi:

1. conduit mints a P-256 key inside the Secure Enclave and shows you the
   public key.
2. **Paste the pairing line** into an SSH session you already have on the
   server (from any computer). It installs the key idempotently and prints
   your session's connection details. Prefer a script? The same installer
   lives in this repo —
   `curl -sSL https://raw.githubusercontent.com/Kakar13/conduit/main/scripts/conduit-pair.sh | sh -s -- '<public key>'`
   — it additionally prints a `conduit://connect` QR (with `qrencode` on the
   server).
3. **Scan the QR** conduit prints (or tap the link) — the profile is
   created and it connects. No typing. Or type host + username if you
   prefer; Face ID unlocks the key and the server's host key is pinned on
   first connect (TOFU).
4. Next launch drops you straight into the terminal, already connecting.

## Privacy

conduit has no backend. No account, no sign-up, no telemetry, no
conduit-operated server anywhere in the data path — and the source in this
repo is the proof:

- **On-device only.** Keys are generated in the Secure Enclave and never
  leave it; server profiles and known hosts live in SwiftData on the
  device; iCloud never sees any of it.
- **Pairing is local.** The pairing line runs inside *your* SSH session on
  *your* server and derives its connection details from the session itself
  — zero outbound calls. The optional helper script is a static file in
  this repo, served by GitHub's CDN; GitHub sees an anonymous download,
  nothing else.
- **No SDKs that phone home.** The only network traffic conduit ever
  originates is SSH to your servers (and, if you use a provider flow
  later, API calls to *your* provider account).
- **No analytics, no crash reporting, no ads, no tracking.**
- **App Store privacy label: Data Not Collected.**

If conduit ever grows a feature that requires a server, that's a bug in
the product, not a feature.

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

- **Handover**: `NWParameters.multipathServiceType = .handover` lets iOS
  migrate the flow between Wi-Fi and cellular without a reconnect, using
  Multipath TCP (RFC 6824) where both ends support it (requires the
  Multipath entitlement; stock EC2 AMIs don't run MPTCP, so the reconnect
  engine below is the real guarantee). The whole SSH stack runs on
  Network.framework's user-space TCP — no BSD sockets involved.
- **Detection**: mobile links rarely fail cleanly — they hang, and vanilla
  TCP (RFC 6298) will sit in retransmission backoff for minutes before
  admitting it. `NWPathMonitor` watches interface availability and kills the
  socket the moment every path drops; TCP keepalive (RFC 1122 §4.2.3.6:
  20 s idle, 10 s interval, 3 probes → black-holed link declared dead in
  ≤ 50 s) catches the quieter failures.
- **Recovery**: `closeFuture` starts a reconnect loop with capped
  exponential backoff (0.5 s → 15 s, 20 attempts; a returning path
  short-circuits the wait). Each attempt replays handshake + auth + pty +
  shell, then flushes the input buffer (≤ 8 KB of keystrokes typed during
  the outage). A generation counter keeps close events from stale,
  deliberately-torn-down transports from triggering phantom reconnects. The
  terminal buffer is never cleared.
- **Remote persistence**: the shell on the far end still dies with TCP. For
  true session persistence set the profile's reattach command to
  `tmux new -A -s main` (or `screen -xRR`) — reconnects then resume the
  exact remote session.

## Security notes

- Private key material is non-exportable by construction (Secure Enclave);
  the SSH side sees only an `ecdsa-sha2-nistp256` public key (RFC 5656) and
  its signatures.
- Face ID is enforced at the app level before the key is loaded, with a
  5-minute reuse window so automatic reconnects don't prompt. To require
  biometry on *every* signature instead, add `.biometryAny` to the
  access-control flags in `SecureEnclaveKeyStore.createKey` (reconnects will
  then prompt).
- Host keys use trust-on-first-use (RFC 7435) with SwiftData persistence;
  the SHA-256 fingerprint (OpenSSH base64 format) is shown before you trust,
  and a changed key is always refused and surfaced as a possible MITM.
- No analytics, no telemetry, no servers of our own.

## License

See [LICENSE](LICENSE).
