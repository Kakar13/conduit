import SwiftTerm
import UIKit

/// The compact row of keys that mobile keyboards are missing: Escape, a
/// latching Control, Tab, arrows (with hold-to-repeat), Home/End, Page
/// Up/Down, and the shell punctuation that is painful to reach (`| ~ ` -`).
///
/// The bar sends through SwiftTerm's own input pipeline, so application
/// cursor mode and the control latch behave exactly as on a hardware
/// keyboard.
final class AccessoryKeyBar: UIInputView {
    private weak var terminal: TerminalView?
    private var ctrlButton: UIButton?
    private var repeatTimer: Timer?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private enum Direction {
        case up, down, left, right
    }

    init(terminal: TerminalView) {
        self.terminal = terminal
        // The system stretches accessory views to the keyboard's width; the
        // frame width here is only a placeholder.
        super.init(
            frame: CGRect(x: 0, y: 0, width: 320, height: 46),
            inputViewStyle: .keyboard
        )
        buildButtons()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controlLatchReset),
            name: .terminalViewControlModifierReset,
            object: terminal
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func buildButtons() {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -5),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -10),
        ])

        stack.addArrangedSubview(makeTextButton("esc") { [weak self] in self?.send([0x1B]) })
        let ctrl = makeTextButton("ctrl") { [weak self] in self?.toggleControl() }
        ctrlButton = ctrl
        stack.addArrangedSubview(ctrl)
        stack.addArrangedSubview(makeTextButton("tab") { [weak self] in self?.send([0x09]) })

        stack.addArrangedSubview(makeArrowButton("chevron.left", direction: .left))
        stack.addArrangedSubview(makeArrowButton("chevron.down", direction: .down))
        stack.addArrangedSubview(makeArrowButton("chevron.up", direction: .up))
        stack.addArrangedSubview(makeArrowButton("chevron.right", direction: .right))

        stack.addArrangedSubview(makeTextButton("|") { [weak self] in self?.send([0x7C]) })
        stack.addArrangedSubview(makeTextButton("~") { [weak self] in self?.send([0x7E]) })
        stack.addArrangedSubview(makeTextButton("`") { [weak self] in self?.send([0x60]) })
        stack.addArrangedSubview(makeTextButton("-") { [weak self] in self?.send([0x2D]) })

        stack.addArrangedSubview(makeTextButton("home") { [weak self] in self?.terminal?.sendKeyHome() })
        stack.addArrangedSubview(makeTextButton("end") { [weak self] in self?.terminal?.sendKeyEnd() })
        stack.addArrangedSubview(makeTextButton("pgup") { [weak self] in self?.send([0x1B, 0x5B, 0x35, 0x7E]) })
        stack.addArrangedSubview(makeTextButton("pgdn") { [weak self] in self?.send([0x1B, 0x5B, 0x36, 0x7E]) })

        let dismiss = makeSymbolButton("keyboard.chevron.compact.down") { [weak self] in
            _ = self?.terminal?.resignFirstResponder()
        }
        stack.addArrangedSubview(dismiss)
    }

    // MARK: - Button factories

    private func style(_ button: UIButton) -> UIButton {
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(UIColor(white: 0.9, alpha: 1), for: .normal)
        button.tintColor = UIColor(white: 0.9, alpha: 1)
        button.backgroundColor = UIColor(white: 1, alpha: 0.12)
        button.layer.cornerRadius = 7
        button.layer.cornerCurve = .continuous
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func makeTextButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = style(UIButton(type: .custom))
        button.setTitle(title, for: .normal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in self?.haptic.impactOccurred() }, for: .touchDown)
        return button
    }

    private func makeSymbolButton(_ symbol: String, action: @escaping () -> Void) -> UIButton {
        let button = style(UIButton(type: .custom))
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.preferredSymbolConfiguration = .init(pointSize: 15, weight: .medium)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in self?.haptic.impactOccurred() }, for: .touchDown)
        return button
    }

    private func makeArrowButton(_ symbol: String, direction: Direction) -> UIButton {
        let button = style(UIButton(type: .custom))
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.preferredSymbolConfiguration = .init(pointSize: 15, weight: .medium)
        button.addAction(UIAction { [weak self] _ in
            self?.haptic.impactOccurred()
            self?.sendArrow(direction)
            self?.startRepeating(direction)
        }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            button.addAction(UIAction { [weak self] _ in self?.stopRepeating() }, for: event)
        }
        return button
    }

    // MARK: - Key actions

    private func send(_ bytes: [UInt8]) {
        terminal?.send(bytes)
    }

    private func sendArrow(_ direction: Direction) {
        switch direction {
        case .up: terminal?.sendKeyUp()
        case .down: terminal?.sendKeyDown()
        case .left: terminal?.sendKeyLeft()
        case .right: terminal?.sendKeyRight()
        }
    }

    /// Control is a one-shot latch: SwiftTerm applies it to the next key and
    /// then clears it, posting `.terminalViewControlModifierReset`.
    private func toggleControl() {
        guard let terminal else { return }
        terminal.controlModifier = !terminal.controlModifier
        updateControlAppearance(latched: terminal.controlModifier)
    }

    @objc private func controlLatchReset() {
        updateControlAppearance(latched: false)
    }

    private func updateControlAppearance(latched: Bool) {
        guard let ctrlButton else { return }
        if latched {
            ctrlButton.backgroundColor = UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
            ctrlButton.setTitleColor(.black, for: .normal)
        } else {
            ctrlButton.backgroundColor = UIColor(white: 1, alpha: 0.12)
            ctrlButton.setTitleColor(UIColor(white: 0.9, alpha: 1), for: .normal)
        }
    }

    // MARK: - Hold-to-repeat

    private func startRepeating(_ direction: Direction) {
        stopRepeating()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.sendArrow(direction)
            }
        }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
