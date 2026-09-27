import AVFoundation
import os
import SwiftUI

/// Live QR scanner used by the pairing flow. The delegate runs on a
/// background-safe detector class; results hop to the main actor.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        QRScannerController(onCode: onCode)
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController {
    private let onCode: @MainActor (String) -> Void
    private let detector: QRDetector
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// AVCaptureSession is documented thread-safe but SDK-non-Sendable, so
    /// it lives in an explicitly-unchecked Sendable box: the only crossing
    /// is the box itself, and start/stop run inside the (nonisolated)
    /// dispatch closure that owns it.
    private final class SessionBox: @unchecked Sendable {
        let session = AVCaptureSession()
    }

    private let box = SessionBox()
    private var statusLabel: UILabel?

    init(onCode: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode
        self.detector = QRDetector(onCode: onCode)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showStatus("Camera unavailable on this device.")
            return
        }

        let output = AVCaptureMetadataOutput()

        let session = box.session
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            showStatus("Camera unavailable on this device.")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(detector, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = await AVCaptureDevice.requestAccess(for: .video)
            default:
                granted = false
            }
            if granted {
                startSession()
            } else {
                showStatus("Camera access is required to scan pairing codes. Enable it in Settings.")
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func startSession() {
        guard !box.session.isRunning else { return }
        let box = self.box
        DispatchQueue.global(qos: .userInitiated).async {
            box.session.startRunning()
        }
    }

    private func stopSession() {
        guard box.session.isRunning else { return }
        let box = self.box
        DispatchQueue.global(qos: .userInitiated).async {
            box.session.stopRunning()
        }
    }

    private func showStatus(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .callout)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        statusLabel = label
    }
}

/// `AVCaptureMetadataOutputObjectsDelegate` callbacks are nonisolated; this
/// detector stays lock-protected until it hands the payload to the main
/// actor exactly once.
final class QRDetector: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: @MainActor (String) -> Void
    private let fired = OSAllocatedUnfairLock(initialState: false)

    init(onCode: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let alreadyFired = fired.withLock { fired -> Bool in
            defer { fired = true }
            return fired
        }
        guard !alreadyFired else { return }

        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              object.type == .qr,
              let value = object.stringValue else { return }

        let onCode = self.onCode
        Task { @MainActor in
            onCode(value)
        }
    }
}

/// Presentable wrapper: camera preview with a title and cancel button.
struct QRScannerSheet: View {
    let onCode: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScannerView { code in
                dismiss()
                onCode(code)
            }
            .ignoresSafeArea()
            .navigationTitle("Scan Pairing QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
