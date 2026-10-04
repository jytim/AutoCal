import Foundation

/// 一門每週重複的課。課堂不是「事件」：只存在 AutoCal 自己的資料裡，
/// 不會寫進 Apple 行事曆，也不會出現在月曆分頁。
struct Course: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// 1 = 週一 … 7 = 週日
    var weekday: Int
    /// 從當天 00:00 起算的分鐘數
    var startMinute: Int
    var endMinute: Int
    var location: String?
    /// 學期第一天與最後一天（都是當天 00:00）
    var termStart: Date
    var termEnd: Date
    /// 停課日（當天 00:00）
    var skipDates: [Date] = []
    /// 使用者指定的顏色（6 位 hex）；nil = 依課名自動配色。
    var colorHex: String?

    static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]
    var weekdayName: String { "週" + Self.weekdayNames[max(0, min(6, weekday - 1))] }
    var timeText: String {
        String(format: "%02d:%02d–%02d:%02d", startMinute / 60, startMinute % 60,
               endMinute / 60, endMinute % 60)
    }
}

/// 某一門課在某一天的實際時段。
struct CourseOccurrence: Identifiable {
    let course: Course
    let start: Date
    let end: Date
    var id: String { "\(course.id.uuidString)-\(start.timeIntervalSince1970)" }
}

/// 模型從課表截圖辨識出的一筆課（還沒確認、還沒有學期範圍）。
/// 課表如果寫的是「第幾節」，由程式用台科大的節次表換算成時間，
/// 不讓模型自己算（實測模型直接輸出時間會對錯列，輸出節次則幾乎全對）。
struct CourseDraft: Identifiable, Decodable {
    let id = UUID()
    var name: String
    var weekday: Int
    var startPeriod: String?
    var endPeriod: String?
    /// 截圖上直接印了上課時間時才有（"HH:mm"）。
    var start: String?
    var end: String?
    var location: String?
    var isSelected = true
    /// 這張截圖看得到星期標題嗎。看不到的話，星期是靠推測的，要請使用者確認。
    var hasHeader = true
    /// 這張截圖看得到左邊的節次／時間欄嗎。看不到就讀不出時間。
    var hasPeriodAxis = true
    /// 課程方塊水平中心點，佔截圖寬度的百分比（0–100）。沒有星期標題時，用它推算星期。
    var xCenter: Double?
    /// 這筆來自第幾張截圖（由匯入流程填入，不來自模型）。
    var sourceIndex = 0
    /// 星期是推測的（來自沒有標題的截圖），確認畫面會標出來。
    var weekdayGuessed = false
    /// 合併時留下的提醒（例如合併後時段變長，可能其實是不同天的兩堂課）。
    var mergeNote: String?

    enum CodingKeys: String, CodingKey {
        case name, weekday, startPeriod, endPeriod, start, end, location, hasHeader, hasPeriodAxis, xCenter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        weekday = (try? c.decode(Int.self, forKey: .weekday)) ?? 0
        startPeriod = Self.flexString(c, .startPeriod)
        endPeriod = Self.flexString(c, .endPeriod)
        start = Self.flexString(c, .start)
        end = Self.flexString(c, .end)
        location = Self.flexString(c, .location)
        hasHeader = (try? c.decodeIfPresent(Bool.self, forKey: .hasHeader)) ?? true
        hasPeriodAxis = (try? c.decodeIfPresent(Bool.self, forKey: .hasPeriodAxis)) ?? true
        if let x = try? c.decodeIfPresent(Double.self, forKey: .xCenter) { xCenter = x }
        else if let s = try? c.decodeIfPresent(String.self, forKey: .xCenter), let x = Double(s) { xCenter = x }
    }

    /// 模型有時把節次回成數字、有時回成字串，兩種都收。
    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: k) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return String(i) }
        return nil
    }

    var startMinute: Int? {
        if let s = start, let m = Self.minutes(s) { return m }
        if let p = startPeriod, let t = Self.periodTimes[p.uppercased()] { return t.start }
        return nil
    }

    var endMinute: Int? {
        if let e = end, let m = Self.minutes(e) { return m }
        if let p = endPeriod, let t = Self.periodTimes[p.uppercased()] { return t.end }
        return nil
    }

    /// 給確認畫面用：「第3–4節」。
    var periodText: String? {
        guard let a = startPeriod, !a.isEmpty else { return nil }
        let b = endPeriod ?? a
        return a == b ? "第\(a)節" : "第\(a)–\(b)節"
    }

    var timeText: String {
        guard let s = startMinute, let e = endMinute else { return "時間不明" }
        return String(format: "%02d:%02d–%02d:%02d", s / 60, s % 60, e / 60, e % 60)
    }

    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 台科大各節上課時間（從 00:00 起算的分鐘；每節 50 分鐘）。
    /// 來源：台科大課程時間及教室代碼表。
    static let periodTimes: [String: (start: Int, end: Int)] = [
        "0": (430, 480),   "1": (490, 540),   "2": (550, 600),   "3": (620, 670),
        "4": (680, 730),   "5": (740, 790),   "6": (800, 850),   "7": (860, 910),
        "8": (930, 980),   "9": (990, 1040),  "10": (1050, 1100),
        "A": (1105, 1155), "B": (1160, 1210), "C": (1215, 1265), "D": (1270, 1320)
    ]
}

extension CourseDraft {
    /// 名字正規化：去掉空白、全形括號轉半形，免得「初級日文 (一)」和「初級日文(一)」被當成不同課。
    static func normalizedName(_ n: String) -> String {
        n.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
    }

    /// 兩個名字算同一門課：正規化後相同，或其中一個是另一個的一部分
    /// （截圖切到邊緣時，模型只讀到殘缺的名字，例如「波動」「報英文」）。
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let x = normalizedName(a), y = normalizedName(b)
        if x == y { return true }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        return short.count >= 2 && long.contains(short)
    }

    /// 最小平方法：用 (星期, 水平位置%) 的點，推出「每往後一個星期，位置移動多少」。
    /// 至少要有兩個不同的星期、兩欄間距至少 5% 寬度才算數。
    private static func fitColumns(_ pts: [(w: Double, x: Double)]) -> (a: Double, b: Double)? {
        guard Set(pts.map(\.w)).count >= 2 else { return nil }
        let n = Double(pts.count)
        let mw = pts.map(\.w).reduce(0, +) / n, mx = pts.map(\.x).reduce(0, +) / n
        let variance = pts.map { ($0.w - mw) * ($0.w - mw) }.reduce(0, +)
        guard variance > 0 else { return nil }
        let b = pts.map { ($0.w - mw) * ($0.x - mx) }.reduce(0, +) / variance
        guard b > 5 else { return nil }
        return (mx - b * mw, b)
    }

    /// 沒有星期標題的截圖：不讓模型猜星期，而是用方塊的水平位置推算。全部截圖都辨識完才做（不受順序影響）：
    /// 1. 錨點：這張圖裡和「有標題的截圖」同名、同時段、而且在有標題那邊只出現在某一天的課，
    ///    星期直接沿用；有兩個以上不同星期的錨點，就用它們替「這一張圖」單獨校正欄位位置
    ///    （圖被左右裁切過、欄位整體偏移也不怕）。
    /// 2. 沒有足夠錨點時，用所有有標題的截圖學到的欄位位置推算（至少要看到兩個不同的星期）。
    /// 3. 都推不出來就維持「星期不明」，由使用者自己選。
    /// 指派出來的星期一律標成「推測」，確認畫面會請使用者確認。
    static func assigningWeekdays(_ drafts: [CourseDraft]) -> [CourseDraft] {
        let header = drafts.filter { $0.hasHeader && (1...7).contains($0.weekday) }
        let global = fitColumns(header.compactMap { d in d.xCenter.map { (Double(d.weekday), $0) } })
        var out = drafts
        let sources = Set(drafts.filter { !$0.hasHeader && $0.weekday == 0 }.map(\.sourceIndex))
        for s in sources {
            let idxs = out.indices.filter { out[$0].sourceIndex == s && !out[$0].hasHeader && out[$0].weekday == 0 }
            var anchors: [Int: Int] = [:]          // 草稿索引 → 沿用的星期
            for i in idxs {
                guard let sm = out[i].startMinute, let em = out[i].endMinute else { continue }
                let days = Set(header.filter {
                    namesMatch($0.name, out[i].name) && $0.startMinute == sm && $0.endMinute == em
                }.map(\.weekday))
                if days.count == 1, let w = days.first { anchors[i] = w }
            }
            let anchorFit = fitColumns(anchors.compactMap { i, w in out[i].xCenter.map { (Double(w), $0) } })
            let model = anchorFit ?? global
            for i in idxs {
                if let w = anchors[i] {
                    out[i].weekday = w; out[i].weekdayGuessed = true; continue
                }
                guard let x = out[i].xCenter, let m = model else { continue }
                let centers = (1...7).compactMap { w -> (w: Int, x: Double)? in
                    let c = m.a + m.b * Double(w)
                    return (c > -5 && c < 105) ? (w, c) : nil
                }
                if let best = centers.min(by: { abs($0.x - x) < abs($1.x - x) }) {
                    out[i].weekday = best.w; out[i].weekdayGuessed = true
                }
            }
        }
        return out
    }

    /// 合併多張截圖辨識出的課：同一門課、同一天，時段重疊或緊接（相隔 20 分鐘內，
    /// 例如連續兩節）就當成同一堂，取聯集；這樣重複拍到的、或被截圖邊界切成兩半的課都會接起來。
    static func merged(_ drafts: [CourseDraft]) -> [CourseDraft] {
        var out: [CourseDraft] = []
        for var d in drafts {
            guard let ds = d.startMinute, let de = d.endMinute else { continue }
            let name = d.name.trimmingCharacters(in: .whitespaces)
            // 星期不明（0）的：如果整份課表裡這門課只在同一天出現，就沿用那一天
            if d.weekday == 0 {
                let days = Set(drafts.filter { $0.weekday != 0 && namesMatch($0.name, name) }.map(\.weekday))
                if days.count == 1, let only = days.first { d.weekday = only }
            }
            if let i = out.firstIndex(where: { o in
                guard let os = o.startMinute, let oe = o.endMinute else { return false }
                return namesMatch(o.name, name)
                    && o.weekday == d.weekday
                    && ds <= oe + 20 && os <= de + 20
            }) {
                var m = out[i]
                // 名字殘缺（被截圖邊緣切到）時，留下較完整的那個
                if normalizedName(name).count > normalizedName(m.name).count { m.name = name }
                let ms = m.startMinute ?? ds, me = m.endMinute ?? de
                let grew = ds < ms || de > me
                if ds < ms { m.startPeriod = d.startPeriod; m.start = d.start }
                if de > me { m.endPeriod = d.endPeriod; m.end = d.end }
                if m.location == nil { m.location = d.location }
                // 一邊是有標題的截圖（可信）、另一邊是推測的：
                // 兩邊同一天、時段也沒有變長 → 推測被可信的那邊印證了，不用再請使用者確認。
                // 時段變長就仍然當成推測的——不能讓「可信」的那一邊把「猜的」洗白，
                // 否則不同天的兩堂課會被無聲併成一堂。
                if m.weekdayGuessed != d.weekdayGuessed && !grew {
                    m.weekdayGuessed = false
                } else if m.weekdayGuessed || d.weekdayGuessed {
                    m.weekdayGuessed = true
                    if grew {
                        m.mergeNote = "和一張沒有星期標題的截圖合併後，時段變長了。如果其實是不同天的兩堂課，請取消勾選這筆，再用「+」手動新增。"
                    }
                }
                out[i] = m
            } else {
                out.append(d)
            }
        }
        return out
    }
}

/// 課表的儲存。優先放在 App Group（讓分享擴充功能、之後的小工具也讀得到），
/// 沒有簽署 App Group 時（例如模擬器的命令列建置）退回 App 自己的資料夾。
@MainActor
final class CourseStore: ObservableObject {
    static let shared = CourseStore()

    @Published private(set) var courses: [Course] = []

    private let fileURL: URL
    private let calendar = Calendar.current

    init() {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup) {
            fileURL = group.appendingPathComponent("courses.json")
        } else {
            let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("courses.json")
        }
        reload()
    }

    // MARK: - 讀寫

    func reload() {
        guard let data = try? Data(contentsOf: fileURL) else { courses = []; return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        courses = (try? dec.decode([Course].self, from: data)) ?? []
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(courses) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ new: [Course]) {
        courses.append(contentsOf: new.map(normalized))
        persist()
    }

    func update(_ course: Course) {
        guard let i = courses.firstIndex(where: { $0.id == course.id }) else { return }
        courses[i] = normalized(course)
        persist()
    }

    func delete(id: UUID) {
        courses.removeAll { $0.id == id }
        persist()
    }

    /// 這門課在這一天停課。
    func skip(courseID: UUID, on day: Date) {
        guard let i = courses.firstIndex(where: { $0.id == courseID }) else { return }
        let d = calendar.startOfDay(for: day)
        if !courses[i].skipDates.contains(d) { courses[i].skipDates.append(d) }
        persist()
    }

    private func normalized(_ c: Course) -> Course {
        var c = c
        c.termStart = calendar.startOfDay(for: c.termStart)
        c.termEnd = calendar.startOfDay(for: c.termEnd)
        return c
    }

    // MARK: - 展開成某一天的實際時段（只在需要時當場算，不另外存每一堂）

    func occurrences(on day: Date) -> [CourseOccurrence] {
        let d = calendar.startOfDay(for: day)
        let w = calendar.component(.weekday, from: d)      // 1 = 週日
        let monday1 = (w == 1) ? 7 : w - 1
        return courses.compactMap { c -> CourseOccurrence? in
            guard c.weekday == monday1, c.termStart <= d, d <= c.termEnd,
                  !c.skipDates.contains(where: { calendar.isDate($0, inSameDayAs: d) }),
                  let s = calendar.date(byAdding: .minute, value: c.startMinute, to: d),
                  let e = calendar.date(byAdding: .minute, value: c.endMinute, to: d)
            else { return nil }
            return CourseOccurrence(course: c, start: s, end: e)
        }
    }
}
