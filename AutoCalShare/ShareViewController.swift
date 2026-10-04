import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

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

    /// 分享擴充功能的記憶體上限很低（約 120MB），所以不把整張圖解碼成 UIImage 再縮小，
    /// 而是用 ImageIO 直接從檔案縮圖：任何格式（HEIC、PNG、WebP、GIF…）都能處理，也不會爆記憶體。
    private func loadImage(from provider: NSItemProvider,
                           completion: @escaping (SharedInput) -> Void) {
        let finish: (Data?) -> Void = { data in
            let result: SharedInput = data.map { .image($0, mime: "image/jpeg") } ?? .none
            DispatchQueue.main.async { completion(result) }
        }
        // 檔案在這個 handler 結束後就會被系統刪掉，所以要在裡面處理完
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            if let url, let jpeg = Self.thumbnailJPEG(from: url) {
                finish(jpeg); return
            }
            // 備援：有些來源只給資料或 UIImage
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { obj, _ in
                switch obj {
                case let image as UIImage:
                    finish(Self.jpeg(from: image))
                case let raw as Data:
                    finish(Self.thumbnailJPEG(from: raw))
                case let url as URL:
                    finish(Self.thumbnailJPEG(from: url))
                default:
                    finish(nil)
                }
            }
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

    /// 長邊縮到 1600px 以內再轉 JPEG，加快上傳與辨識。
    private static let maxSide = 1600

    private static func thumbnailJPEG(from url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnailJPEG(from: src)
    }

    private static func thumbnailJPEG(from data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailJPEG(from: src)
    }

    private static func thumbnailJPEG(from src: CGImageSource) -> Data? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // 套用 EXIF 方向
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
    }

    private static func jpeg(from image: UIImage) -> Data? {
        let long = max(image.size.width, image.size.height)
        guard long > CGFloat(maxSide) else { return image.jpegData(compressionQuality: 0.85) }
        let scale = CGFloat(maxSide) / long
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.85)
    }

    func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
