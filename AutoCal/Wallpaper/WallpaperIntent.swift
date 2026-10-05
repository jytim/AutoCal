import AppIntents
import UniformTypeIdentifiers

/// 給「捷徑」用的動作：產生今天的桌布圖。
/// 在捷徑裡接上「設定桌布」動作，再用個人自動化定時或在特定時機執行。
struct TodayWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "產生今日鎖定畫面桌布"
    static var description = IntentDescription(
        "把今天剩下的課堂、行程和空堂畫成一張鎖定畫面桌布圖片，可接在「設定桌布」動作上。")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let data = WallpaperRenderer.png() else {
            throw WallpaperError.renderFailed
        }
        return .result(value: IntentFile(data: data, filename: "JustAdd-wallpaper.png", type: .png))
    }
}

enum WallpaperError: Error, CustomLocalizedStringResourceConvertible {
    case renderFailed
    var localizedStringResource: LocalizedStringResource { "桌布圖產生失敗" }
}

struct AutoCalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodayWallpaperIntent(),
                    phrases: ["用 \(.applicationName) 產生今日桌布"],
                    shortTitle: "今日桌布",
                    systemImageName: "photo")
    }
}
