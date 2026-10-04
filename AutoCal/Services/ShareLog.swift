import Foundation

/// 分享擴充功能的簡單足跡紀錄，寫在 App Group 共用資料夾，主 App 的設定裡可以看。
/// 擴充功能閃退時看不到錯誤訊息，靠這個知道它最後做到哪一步。
enum ShareLog {
    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)?
            .appendingPathComponent("share-log.txt")
    }

    static func write(_ message: String) {
        guard let url = fileURL else { return }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        trimIfNeeded(url)
    }

    static func read() -> String {
        guard let url = fileURL, let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    static func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }

    /// 只留最後約 200 行。
    private static func trimIfNeeded(_ url: URL) {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 200 else { return }
        try? (lines.suffix(200).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
