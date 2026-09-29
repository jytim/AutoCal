import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// 分享進來的內容：一張圖片、或一段文字。
enum SharedInput {
    case image(Data, mime: String)
    case text(String)
    case none
}

/// Share Extension 進入點：從分享內容取出圖片或文字，交給 SwiftUI 畫面處理。
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedInput { [weak self] input in
            guard let self else { return }
            let root = ShareRootView(input: input, onClose: { self.close() })
            let host = UIHostingController(rootView: root)
            self.addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    /// 優先取圖片；沒有圖片就取文字（含網址、純文字）。
    private func loadSharedInput(completion: @escaping (SharedInput) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            completion(.none); return
        }

        let imageType = UTType.image.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(imageType) }) {
            loadImage(from: provider, completion: completion)
            return
        }

        let textType = UTType.text.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            loadText(from: provider, completion: completion)
            return
        }

        completion(.none)
    }

    private func loadImage(from provider: NSItemProvider,
                           completion: @escaping (SharedInput) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { obj, _ in
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
            if let d = data, let shrunk = Self.downscaleIfNeeded(d) {
                data = shrunk; mime = "image/jpeg"
            }
            let result: SharedInput = data.map { .image($0, mime: mime) } ?? .none
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func loadText(from provider: NSItemProvider,
                          completion: @escaping (SharedInput) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { obj, _ in
            let text: String?
            switch obj {
            case let s as String: text = s
            case let url as URL: text = url.absoluteString
            case let data as Data: text = String(data: data, encoding: .utf8)
            default: text = nil
            }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: SharedInput = (trimmed?.isEmpty == false) ? .text(trimmed!) : .none
            DispatchQueue.main.async { completion(result) }
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
