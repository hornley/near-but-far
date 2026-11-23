import AVFoundation
import SwiftUI

enum PairingScannerState: Equatable {
    case unpaired, scanning, waitingForMacApproval, paired, expired, qrMismatch, untrustedMac, cameraUnavailable, storageUnavailable, bluetoothUnavailable

    var title: String {
        switch self {
        case .unpaired: "Not paired"
        case .scanning: "Scan the code on your Mac."
        case .waitingForMacApproval: "Waiting for Mac approval."
        case .paired: "Paired."
        case .expired: "Code expired"
        case .qrMismatch: "QR code mismatch"
        case .untrustedMac: "Mac identity mismatch"
        case .cameraUnavailable: "Camera unavailable"
        case .storageUnavailable: "Secure storage unavailable"
        case .bluetoothUnavailable: "Bluetooth unavailable"
        }
    }

    var nextStep: String {
        switch self {
        case .unpaired: "Open Pair iPhone on your Mac, then scan its one-use code."
        case .scanning: ""
        case .waitingForMacApproval: "Approve this phone on your Mac. Keep this screen open."
        case .paired: "This phone is paired with your Mac."
        case .expired: "The code expired. Create a new code on your Mac and scan it again."
        case .qrMismatch: "This code does not match the Mac. Scan a fresh code."
        case .untrustedMac: "This is not the saved Mac. Your pairing is unchanged."
        case .cameraUnavailable: "Allow camera access in iPhone Settings to scan a code."
        case .storageUnavailable: "Pairing is unavailable. Restart the app and try again."
        case .bluetoothUnavailable: "Turn on Bluetooth in Settings, then retry pairing."
        }
    }

    var retryTitle: String? {
        switch self {
        case .expired: "Scan a new code"
        case .qrMismatch: "Scan a new code"
        case .unpaired: "Scan Mac QR code"
        case .untrustedMac: "Retry connection"
        case .cameraUnavailable: "Try camera again"
        case .scanning, .waitingForMacApproval, .paired, .storageUnavailable, .bluetoothUnavailable: nil
        }
    }
}

struct PairingScannerView: View {
    let state: PairingScannerState
    let onPayload: (String) -> Void
    let onCameraUnavailable: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(state.title).font(.title2.bold())
                if !state.nextStep.isEmpty {
                    Text(state.nextStep).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if state == .scanning {
                    QRScanner(onPayload: onPayload, onCameraUnavailable: onCameraUnavailable)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                if let retryTitle = state.retryTitle {
                    Button(retryTitle, action: onRetry).buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(state == .paired ? "Done" : "Cancel", action: onCancel)
                }
            }
        }
    }

}

private struct QRScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void
    let onCameraUnavailable: () -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onPayload = onPayload
        controller.onCameraUnavailable = onCameraUnavailable
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onPayload = onPayload
        controller.onCameraUnavailable = onCameraUnavailable
    }
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onPayload: ((String) -> Void)?
    var onCameraUnavailable: (() -> Void)?
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.nearbutfar.phone.qr-capture")
    private var configurationRequested = false
    private var configurationComplete = false
    private var isVisible = false
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted { onCameraUnavailable?(); return }
        guard status == .authorized else { return }
        configureCaptureIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted else { self.onCameraUnavailable?(); return }
                    self.configureCaptureIfNeeded()
                }
            }
        case .denied, .restricted:
            onCameraUnavailable?()
        @unknown default:
            onCameraUnavailable?()
        }
        if configurationComplete { installPreviewAndStart() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isVisible = false
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureCaptureIfNeeded() {
        guard !configurationRequested else {
            if configurationComplete { installPreviewAndStart() }
            return
        }
        configurationRequested = true
        captureQueue.async { [weak self] in
            guard let self else { return }
            var configured = false
            if let camera = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) {
                self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                if self.session.canAddOutput(output) {
                    self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.qr]
                    configured = true
                }
            }
            DispatchQueue.main.async {
                self.configurationComplete = configured
                guard configured else { self.onCameraUnavailable?(); return }
                if self.isVisible { self.installPreviewAndStart() }
            }
        }
    }

    private func installPreviewAndStart() {
        guard isVisible, configurationComplete else { return }
        if previewLayer == nil {
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview
        }
        captureQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        onPayload?(value)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isVisible, self.configurationComplete else { return }
            self.installPreviewAndStart()
        }
    }
}
