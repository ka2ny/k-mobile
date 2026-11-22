import SwiftUI
import AVFoundation

/// The camera, reading one QR code (the computer's pairing code, or a k-chain's setup code) and handing back its text.
struct QRScannerView: UIViewControllerRepresentable {
    var found: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController(); c.found = found; return c
    }
    func updateUIViewController(_ c: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var found: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            // a frame where the code goes
            let frame = CAShapeLayer()
            let side = min(view.bounds.width, view.bounds.height) * 0.62
            frame.path = UIBezierPath(roundedRect: CGRect(x: (view.bounds.width - side) / 2, y: (view.bounds.height - side) / 2, width: side, height: side), cornerRadius: 28).cgPath
            frame.strokeColor = UIColor(white: 1, alpha: 0.85).cgColor
            frame.fillColor = UIColor.clear.cgColor
            frame.lineWidth = 2
            view.layer.addSublayer(frame)
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let code = objects.first as? AVMetadataMachineReadableCodeObject, let text = code.stringValue else { return }
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            found?(text)
        }
    }
}
