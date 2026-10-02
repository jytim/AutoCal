import SwiftUI
import UIKit

/// 把桌布內容畫成一張和這支手機螢幕同尺寸的圖片。
@MainActor
enum WallpaperRenderer {
    /// 螢幕尺寸（pt）與倍率。拿不到時退回 iPhone 15 Pro Max 的尺寸。
    private static func screen() -> (size: CGSize, scale: CGFloat) {
        let b = UIScreen.main.bounds.size
        let s = UIScreen.main.scale
        if b.width > 100, b.height > 100, s > 0 { return (b, s) }
        return (CGSize(width: 430, height: 932), 3)
    }

    static func image(for day: Date = Date(), now: Date = Date()) -> UIImage? {
        let (size, scale) = screen()
        let budget = WallpaperCanvas.listBudget(forHeight: size.height)
        let content = WallpaperContentBuilder.build(day: day, now: now, budget: budget)
        let view = WallpaperCanvas(content: content)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }

    static func png(for day: Date = Date(), now: Date = Date()) -> Data? {
        image(for: day, now: now)?.pngData()
    }
}
