import Foundation

/// 校園行事曆上的單一事件（從 ICS 解析出來）。
struct CampusEvent {
    let title: String
    let start: Date
    let end: Date?
}

/// 抓取並搜尋校園行事曆（ICS）。抓取在手機端進行，再把事件清單交給 LLM 比對查詢。
struct CampusCalendarService {

    enum CalError: LocalizedError {
        case noURL
        case fetchFailed(String)
        case empty
        var errorDescription: String? {
            switch self {
            case .noURL: return "尚未設定校園行事曆網址"
            case .fetchFailed(let s): return "抓取行事曆失敗：\(s)"
            case .empty: return "行事曆沒有可用的事件"
            }
        }
    }

    private let llm = LLMClient()

    /// 用自然語言查詢校園行事曆，回傳對應的 ParsedItem（可直接排入）。
    func search(query: String, now: Date = Date()) async throws -> [ParsedItem] {
        guard let url = AppConfig.campusCalendarURL else { throw CalError.noURL }

        let ics: String
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw CalError.fetchFailed("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            ics = String(data: data, encoding: .utf8) ?? ""
        } catch let e as CalError {
            throw e
        } catch {
            throw CalError.fetchFailed(error.localizedDescription)
        }

        let events = Self.parseICS(ics)
        guard !events.isEmpty else { throw CalError.empty }

        // 只保留今天（含）之後、一年內的事件，縮小給模型的清單。
        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        let today = Calendar.current.startOfDay(for: now)
        let upcoming = events
            .filter { $0.start >= today && $0.start <= oneYear }
            .sorted { $0.start < $1.start }

        let pool = upcoming.isEmpty ? events.sorted { $0.start < $1.start } : upcoming
        return try await llm.matchCalendar(query: query, events: Array(pool.prefix(120)), now: now)
    }

    // MARK: - ICS 解析

    /// 極簡 ICS 解析：取每個 VEVENT 的 SUMMARY / DTSTART / DTEND。
    static func parseICS(_ raw: String) -> [CampusEvent] {
        let unfolded = unfold(raw)
        var events: [CampusEvent] = []

        for block in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            let body = block.components(separatedBy: "END:VEVENT").first ?? block
            guard let summary = value(of: "SUMMARY", in: body), !summary.isEmpty,
                  let startLine = line(prefix: "DTSTART", in: body),
                  let start = parseICSDate(startLine) else { continue }
            let end = line(prefix: "DTEND", in: body).flatMap { parseICSDate($0) }
            events.append(CampusEvent(title: summary, start: start, end: end))
        }
        return events
    }

    /// ICS 會把長行以「換行 + 空白」折行，先還原。
    private static func unfold(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n ", with: "")
         .replacingOccurrences(of: "\n ", with: "")
         .replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// 取 `KEY:value`（KEY 後可能帶參數，如 DTSTART;VALUE=DATE）。
    private static func value(of key: String, in body: String) -> String? {
        guard let l = line(prefix: key, in: body),
              let colon = l.firstIndex(of: ":") else { return nil }
        return String(l[l.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func line(prefix: String, in body: String) -> String? {
        body.split(separator: "\n").first {
            $0.hasPrefix(prefix + ":") || $0.hasPrefix(prefix + ";")
        }.map(String.init)
    }

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f
    }()

    /// 解析像 `DTSTART;VALUE=DATE:20251020` 或 `DTSTART:20251020T090000` 的整行。
    private static func parseICSDate(_ fullLine: String) -> Date? {
        guard let colon = fullLine.firstIndex(of: ":") else { return nil }
        var v = String(fullLine[fullLine.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasSuffix("Z") { v.removeLast() }   // 粗略當本地時間處理
        return dateTime.date(from: v) ?? dateOnly.date(from: v)
    }
}
