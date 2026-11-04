import AppKit
import AVFoundation
import CoreImage
import SwiftUI

struct MacQRScanner: NSViewRepresentable {
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onFailure: onFailure) }

    func makeNSView(context: Context) -> NSView {
        let view = PreviewView(session: context.coordinator.session)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: NSView {
        private let preview: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            preview.frame = bounds
        }
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        let session = AVCaptureSession()
        private let onCode: (String) -> Void
        private let onFailure: (String) -> Void
        private let sessionQueue = DispatchQueue(label: "android-transfer-camera-session")
        private let frameQueue = DispatchQueue(label: "android-transfer-camera-frames")
        private let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                          context: CIContext(),
                                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        private let stateLock = NSLock()
        private var stopped = false
        private var scanned = false
        private var lastScan = Date.distantPast

        init(onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onFailure = onFailure
        }

        func start() {
            sessionQueue.async { [self] in
                guard !stateLock.withLock({ stopped }) else { return }
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    fail("Kamera başlatılamadı. Telefonun bağlantı kodunu yapıştırabilirsiniz.")
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .medium
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    fail("Kamera görüntüsü açılamadı. Telefonun bağlantı kodunu yapıştırabilirsiniz.")
                    return
                }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    fail("Kamera görüntüsü okunamadı. Telefonun bağlantı kodunu yapıştırabilirsiniz.")
                    return
                }
                session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: frameQueue)
                session.commitConfiguration()
                guard !stateLock.withLock({ stopped }) else { return }
                session.startRunning()
            }
        }

        func stop() {
            stateLock.withLock { stopped = true }
            sessionQueue.async { [self] in
                if session.isRunning { session.stopRunning() }
            }
        }

        private func fail(_ message: String) {
            DispatchQueue.main.async { [self] in
                if !stateLock.withLock({ stopped }) { onFailure(message) }
            }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard !stateLock.withLock({ stopped || scanned }),
                  Date().timeIntervalSince(lastScan) >= 0.2,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let detector else { return }
            lastScan = Date()
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let feature = detector.features(in: image).compactMap({ $0 as? CIQRCodeFeature }).first,
                  let value = feature.messageString,
                  value.hasPrefix("androidtransfer://pair?") else { return }
            stateLock.withLock { scanned = true }
            DispatchQueue.main.async { [self] in
                if !stateLock.withLock({ stopped }) { onCode(value) }
            }
        }
    }
}
