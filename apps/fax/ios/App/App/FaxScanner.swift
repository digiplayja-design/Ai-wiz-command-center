import Capacitor
import UIKit
import VisionKit

final class FaxViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(FaxScanner())
    }
}

@objc(FaxScanner)
final class FaxScanner: CAPPlugin, CAPBridgedPlugin, VNDocumentCameraViewControllerDelegate {
    let identifier = "FaxScanner"
    let jsName = "FaxScanner"
    let pluginMethods = [CAPPluginMethod(name: "scan", returnType: CAPPluginReturnPromise)]
    private var pending: CAPPluginCall?

    @objc func scan(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard VNDocumentCameraViewController.isSupported else {
                call.reject("Scanning is unavailable on this device.")
                return
            }
            guard self.pending == nil, let presenter = self.bridge?.viewController,
                  presenter.presentedViewController == nil else {
                call.reject("Close the open sheet and try again.")
                return
            }
            self.pending = call
            let camera = VNDocumentCameraViewController()
            camera.delegate = self
            presenter.present(camera, animated: true)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        let call = pending
        pending = nil
        controller.dismiss(animated: true) { call?.resolve(["status": "cancel"]) }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        let call = pending
        pending = nil
        controller.dismiss(animated: true) { call?.reject("The scanner could not complete this scan.") }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        guard let call = pending else { return }
        pending = nil
        controller.dismiss(animated: true) {
            guard (1...24).contains(scan.pageCount) else {
                call.reject("Scan between 1 and 24 pages per batch.")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                var files: [URL] = []
                do {
                    for index in 0..<scan.pageCount {
                        try autoreleasepool {
                            let image = scan.imageOfPage(at: index)
                            let scale = min(1, 1800 / max(image.size.width, image.size.height))
                            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                            let format = UIGraphicsImageRendererFormat()
                            format.scale = 1
                            format.opaque = true
                            let page = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                                image.draw(in: CGRect(origin: .zero, size: size))
                            }
                            guard let data = page.jpegData(compressionQuality: 0.85) else {
                                throw CocoaError(.fileWriteUnknown)
                            }
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fax-scan-" + UUID().uuidString + ".jpg")
                            try data.write(to: url, options: [.atomic, .completeFileProtection])
                            files.append(url)
                        }
                    }
                    call.resolve(["status": "success", "scannedImages": files.map { $0.absoluteString }])
                } catch {
                    files.forEach { try? FileManager.default.removeItem(at: $0) }
                    call.reject("A scanned page could not be saved.")
                }
            }
        }
    }
}
