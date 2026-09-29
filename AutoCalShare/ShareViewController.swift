import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share Extension 進入點：從分享內容取出圖片，交給 SwiftUI 畫面處理。
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedImage { [weak self] data, mime in
            guard let self else { return }
            let root = ShareRootView(
                imageData: data,
                mimeType: mime,
                onClose: { self.close() }
            )
            let host = UIHostingController(rootView: root)
            self.addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    /// 從 extensionContext 找出第一張圖片，回傳原始資料與 MIME type。
    private func loadSharedImage(completion: @escaping (Data?, String) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            completion(nil, "image/jpeg"); return
        }
        let imageType = UTType.image.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(imageType) })
        else { completion(nil, "image/jpeg"); return }

        provider.loadItem(forTypeIdentifier: imageType, options: nil) { obj, _ in
            var data: Data?
            var mime = "image/jpeg"
            switch obj {
            case let url as URL:
                data = try? Data(contentsOf: url)
                if url.pathExtension.lowercased() == "png" { mime = "image/png" }
            case let image as UIImage:
                data = image.jpegData(compressionQuality: 0.85)
            case let raw as Data:
                data = raw
            default:
                break
            }
            // 壓縮過大的截圖，避免 base64 過長
            if let d = data, let shrunk = Self.downscaleIfNeeded(d) {
                data = shrunk; mime = "image/jpeg"
            }
            DispatchQueue.main.async { completion(data, mime) }
        }
    }

    /// 長邊超過 1600px 就縮小，加快上傳與辨識。
    private static func downscaleIfNeeded(_ data: Data, maxSide: CGFloat = 1600) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let longSide = max(img.size.width, img.size.height)
        guard longSide > maxSide else { return nil }
        let scale = maxSide / longSide
        let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.85)
    }

    func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
