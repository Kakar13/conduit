import SwiftTerm
import SwiftUI
import UIKit

/// Shared handle so the SwiftUI screen can feed remote output into the
/// UIKit terminal view.
@MainActor
final class TerminalHandle {
    weak var view: TerminalView?
}

/// Wraps SwiftTerm's `TerminalView`: a dark, Metal-accelerated terminal
/// surface with our compact accessory key bar above the keyboard.
struct TerminalViewRepresentable: UIViewRepresentable {
    let session: SSHSession
    let handle: TerminalHandle

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = UIColor(white: 0.04, alpha: 1)
        view.nativeForegroundColor = UIColor(white: 0.92, alpha: 1)
        view.caretColor = UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
        view.selectedTextBackgroundColor = UIColor(white: 0.28, alpha: 1.0)
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        view.inputAccessoryView = AccessoryKeyBar(terminal: view)
        handle.view = view
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Metal must be enabled after the view is in a window.
        if !context.coordinator.didEnableMetal, uiView.window != nil {
            context.coordinator.didEnableMetal = true
            try? uiView.setUseMetal(true)
        }
        // Keep the last line scrollable above the persistent accessory bar.
        if uiView.contentInset.bottom != AccessoryKeyBar.barHeight {
            uiView.contentInset.bottom = AccessoryKeyBar.barHeight
            uiView.verticalScrollIndicatorInsets.bottom = AccessoryKeyBar.barHeight
        }
        if context.coordinator.shouldFocus {
            context.coordinator.shouldFocus = false
            _ = uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        uiView.updateUiClosed()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        private let session: SSHSession
        var didEnableMetal = false
        var shouldFocus = true

        init(session: SSHSession) {
            self.session = session
        }

        /// Keystrokes from the terminal (software + hardware keyboard,
        /// accessory bar) go straight into the SSH bridge.
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            Task { await session.send(bytes) }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { await session.resize(cols: newCols, rows: newRows) }
        }

        func bell(source: TerminalView) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.string = String(data: content, encoding: .utf8)
        }

        func clipboardRead(source: TerminalView) -> Data? {
            UIPasteboard.general.string?.data(using: .utf8)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func scrolled(source: TerminalView, position: Double) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
