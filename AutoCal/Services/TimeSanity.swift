import Foundation

/// 不靠模型的時間防線：
/// 1. 送出前把「10.」這類簡寫改成「10點」，模型才不會把它當成沒有時間；
/// 2. 解析後核對使用者寫的幾點、以及日期有沒有已經過去，對不上就在卡片上警告。
enum TimeSanity {
    private static var taipei: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return c
    }()

    // MARK: - 1. 送出前改寫

    /// 「10.吃早餐」→「10點吃早餐」。
    /// 只在數字後面「緊接著文字」時才改（避免動到小數點 3.5、條列 1. 後面有空白的情況）。
    static func normalize(_ text: String) -> String {
        let pattern = #"(?<![\d.．])(\d{1,2})[.．。](?=\p{L})"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: "$1點")
    }

    // MARK: - 1b. 相對日期（今天、明天、後天）用程式修正

    /// 文字裡「恰好只有一個」相對日期詞（今天/明天/後天/大後天），而且沒有星期、月、日期數字時，
    /// 所有項目都應該落在那一天——模型偶爾會把「後天」算成差一兩天，這裡直接用程式算出正確日期並修正，
    /// 保留原本的時刻。不符合上述條件（例如同時寫了「週五」）就不動，交給後面的警告處理。
    static func correctRelativeDay(_ items: [ParsedItem], text: String, now: Date = Date()) -> [ParsedItem] {
        // 長的詞要先比，才不會把「大後天」當成「後天」
        let words: [(String, Int)] = [("大後天", 3), ("後天", 2), ("明天", 1), ("明晚", 1), ("明早", 1),
                                      ("今天", 0), ("今晚", 0), ("今早", 0)]
        var rest = text
        var offsets = Set<Int>()
        for (w, off) in words where rest.contains(w) {
            offsets.insert(off)
            rest = rest.replacingOccurrences(of: w, with: "")
        }
        guard offsets.count == 1, let off = offsets.first else { return items }

        // 有星期、月、日期數字就不改（那些可能指別的日子）
        let blockers = #"[週周]|星期|禮拜|礼拜|月|\d{1,2}\s*/\s*\d{1,2}|\d{4}\s*[-/.]\s*\d"#
        if rest.range(of: blockers, options: .regularExpression) != nil { return items }

        guard let target = taipei.date(byAdding: .day, value: off, to: taipei.startOfDay(for: now)) else { return items }
        return items.map { item in
            guard let s = item.start else { return item }
            let sameDay = taipei.isDate(s, inSameDayAs: target)
            if sameDay { return item }
            var it = item
            let t = taipei.dateComponents([.hour, .minute, .second], from: s)
            var c = taipei.dateComponents([.year, .month, .day], from: target)
            c.hour = t.hour; c.minute = t.minute; c.second = t.second
            guard let fixed = taipei.date(from: c) else { return item }
            let delta = fixed.timeIntervalSince(s)
            it.start = fixed
            if let e = it.end { it.end = e.addingTimeInterval(delta) }
            return it
        }
    }

    // MARK: - 2. 解析後核對

    /// 使用者在文字裡寫出的「幾點」（0–24）。只認阿拉伯數字，「3小時」這類時間長度不算。
    static func explicitHours(in text: String) -> [Int] {
        let pattern = #"(?<!\d)(\d{1,2})\s*(?:點|時|:|：)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            Int(ns.substring(with: $0.range(at: 1)))
        }.filter { (0...24).contains($0) }
    }

    /// 解析出的小時（0–23）是否和使用者寫的小時吻合（12 小時制與 24 小時制都算）。
    private static func matches(hour h: Int, writtenHour w: Int) -> Bool {
        h == w || h == w % 12 || h == (w % 12) + 12
    }

    /// 為可疑的項目填入 timeWarning。`text` 請傳入送給模型的文字。
    static func annotate(_ items: [ParsedItem], text: String, now: Date = Date()) -> [ParsedItem] {
        let written = explicitHours(in: text)
        let timed = items.filter { $0.type == .event && !$0.allDay && $0.start != nil }
        let hm = DateFormatter()
        hm.locale = Locale(identifier: "en_US_POSIX")
        hm.timeZone = taipei.timeZone
        hm.dateFormat = "HH:mm"

        return items.map { item in
            var it = item
            var notes: [String] = []

            if !written.isEmpty {
                if let s = it.start, it.type == .event, !it.allDay {
                    let h = taipei.component(.hour, from: s)
                    if !written.contains(where: { matches(hour: h, writtenHour: $0) }) {
                        notes.append("你寫的是 \(written[0]) 點，但解析成 \(hm.string(from: s))，請確認時間。")
                    }
                } else if timed.isEmpty {
                    notes.append("你寫了 \(written[0]) 點，但這筆沒有帶入時間，請確認。")
                }
            }

            if let s = it.start {
                let isPast: Bool
                if it.type == .event && !it.allDay {
                    isPast = s < now.addingTimeInterval(-15 * 60)
                } else {
                    isPast = taipei.startOfDay(for: s) < taipei.startOfDay(for: now)
                }
                if isPast { notes.append("這個時間已經過了，請確認日期。") }
            }

            it.timeWarning = notes.isEmpty ? nil : notes.joined(separator: " ")
            return it
        }
    }
}
