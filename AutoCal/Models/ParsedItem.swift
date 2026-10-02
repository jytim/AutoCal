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

    // MARK: 衝突偵測（由 ConflictChecker 填入，不來自 LLM 的 JSON）

    /// 和這筆時間重疊的既有行程。
    struct ConflictInfo: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let start: Date
        let end: Date
    }

    /// 有衝突時，使用者選擇的處理方式。只有使用者能改，AI 不會替使用者選。
    enum Resolution: String {
        case none       // 沒有衝突
        case undecided  // 有衝突，使用者還沒選
        case overlap    // 照原時間排，和既有行程並行
        case move       // 改到建議的空檔
        case skip       // 不加入（只能由使用者選）
    }

    var conflicts: [ConflictInfo] = []
    /// 當天找到的最近空檔（同樣長度）。
    var suggestedStart: Date?
    var resolution: Resolution = .none
    /// AI 建議的處理方式（只供參考，不會自動套用）。
    var aiRecommendation: Resolution?
    /// AI 判斷能否同時進行；nil 表示沒判斷或判斷失敗。
    var aiCanOverlap: Bool?
    /// AI 對「能不能同時做」的判斷理由。
    var aiNote: String?

    // MARK: 紀錄用

    /// AI 最初解析出的時間（使用者之後在卡片上改時間也不會覆蓋）。
    var aiStart: Date?
    var aiEnd: Date?
    /// 寫入行事曆時附在行程備註裡的決策紀錄。
    var calendarNote: String?

    // LLM 回傳的 JSON 只有這些欄位；其餘欄位由 app 自己補。
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
