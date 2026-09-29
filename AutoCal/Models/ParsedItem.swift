import Foundation

/// LLM 解析出的單一項目：一個行程(event)或一個待辦(todo)。
struct ParsedItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case event
        case todo
    }

    var id = UUID()
    var type: Kind
    var title: String
    var start: Date?
    var end: Date?
    var location: String?
    var allDay: Bool
    /// 使用者是否選取要加入（確認卡片上可勾選）。
    var isSelected: Bool = true

    // LLM 回傳的 JSON 只有這些欄位；id/isSelected 由 app 自己補。
    enum CodingKeys: String, CodingKey {
        case type, title, start, end, location, allDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.type = (try? c.decode(Kind.self, forKey: .type)) ?? .event
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "未命名"
        self.start = ParsedItem.decodeDate(c, .start)
        self.end = ParsedItem.decodeDate(c, .end)
        self.location = try? c.decodeIfPresent(String.self, forKey: .location)
        self.allDay = (try? c.decodeIfPresent(Bool.self, forKey: .allDay)) ?? false
        self.isSelected = true
    }

    init(type: Kind, title: String, start: Date?, end: Date?,
         location: String? = nil, allDay: Bool = false) {
        self.type = type
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.allDay = allDay
    }

    /// 容忍多種 ISO8601 寫法（有/無時區、有/無秒）。
    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>,
                                   _ key: CodingKeys) -> Date? {
        guard let s = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil,
              !s.isEmpty else { return nil }
        return DateParsing.parse(s)
    }
}

enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    /// 沒有時區時，當成台北時間。
    private static let noZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func parse(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s) ?? noZone.date(from: s)
    }
}
