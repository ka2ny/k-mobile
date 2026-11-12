import AVFoundation
import SwiftUI

/// Reads one QR code with the back camera and hands its text back. Nothing is recorded: the session
/// stops at the first code, when the sheet goes, or when the app leaves the foreground.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onProblem: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        controller.onProblem = onProblem
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onProblem: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: configure()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    Task { @MainActor in
                        if granted { self.configure() } else { self.onProblem?(Self.denied) }
                    }
                }
            default: onProblem?(Self.denied)
            }
        }

        static let denied = "The camera is off for k-hole. Turn it on in Settings → k-hole → Camera, or type the address."

        private func configure() {
            guard let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input)
            else { onProblem?("This phone has no camera k-hole can use. Type the address instead."); return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { onProblem?("The camera couldn't read codes. Type the address instead."); return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stop()
        }

        private func stop() {
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                                        from connection: AVCaptureConnection) {
            guard let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            MainActor.assumeIsolated {
                guard !done else { return }
                done = true
                stop()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCode?(text)
            }
        }
    }
}

/// The scanner as a sheet: a frosted frame over the camera, the words of what to point at, and the
/// reason in plain words when it can't read (no camera, camera off, a code that isn't k-hole's).
struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (AppModel.ScannedCode) -> Void
    @State private var problem: String?
    @State private var scanKey = 0

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(
                    onCode: { text in
                        if let code = AppModel.readScannedCode(text) {
                            onCode(code)
                            dismiss()
                        } else {
                            problem = "That code isn't a k-hole pairing code. Open Settings → Remote on your computer and scan the code there."
                            scanKey += 1
                        }
                    },
                    onProblem: { problem = $0 }
                )
                .id(scanKey)
                .ignoresSafeArea()
                VStack(spacing: Design.gap) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .accessibilityHidden(true)
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Point at the code in Settings → Remote on your computer.")
                            .font(.callout.weight(.medium))
                        if let problem {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Design.caution).frame(width: 7, height: 7).accessibilityHidden(true)
                                Text(problem).font(.callout).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.inset)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
                    .padding(Design.inset)
                }
            }
            .navigationTitle("Scan to pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
