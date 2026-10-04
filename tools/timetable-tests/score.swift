import Foundation
struct Truth: Codable { let name: String; let weekday: Int; let start: Int; let end: Int }
struct Scenario: Codable { let name: String; let images: [String]; let truth: [Truth] }
let manifest = try! JSONDecoder().decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: "manifest.json")))
func load(_ im: String) -> [CourseDraft] {
    let d = try! Data(contentsOf: URL(fileURLWithPath: "raw_" + im.replacingOccurrences(of: ".jpg", with: ".json")))
    return try! JSONDecoder().decode([CourseDraft].self, from: d)
}
for sc in manifest {
    for order in [sc.images, sc.images.reversed()] {
        var all: [CourseDraft] = []
        var rejected = 0
        for (idx, im) in order.enumerated() {
            var ds = load(im)
            if !ds.isEmpty, ds.allSatisfy({ !$0.hasPeriodAxis && $0.start == nil && $0.end == nil }) { rejected += 1; continue }
            for k in ds.indices { ds[k].sourceIndex = idx }
            all += ds
        }
        let res = CourseDraft.merged(CourseDraft.assigningWeekdays(all))
        let got = res.map { (CourseDraft.normalizedName($0.name), $0.weekday, $0.startMinute ?? -1, $0.endMinute ?? -1) }
        var missing: [String] = [], matched = 0
        var pool = got
        for t in sc.truth {
            if let i = pool.firstIndex(where: { $0.0 == CourseDraft.normalizedName(t.name) && $0.1 == t.weekday && $0.2 == t.start && $0.3 == t.end }) { matched += 1; pool.remove(at: i) }
            else { missing.append("\(t.name) 週\(t.weekday) \(t.start)-\(t.end)") }
        }
        let extra = pool.map { "\($0.0) 週\($0.1) \($0.2)-\($0.3)" }
        let guessed = res.filter(\.weekdayGuessed).count
        let tag = order == sc.images ? "順" : "逆"
        print("\(sc.name) [\(tag)]: \(matched)/\(sc.truth.count) 對, 多出 \(extra.count), 缺少 \(missing.count), 待確認 \(guessed)\(rejected > 0 ? ", 拒絕 \(rejected) 張" : "")")
        if order == sc.images { for m in missing { print("     缺少:", m) }; for e in extra { print("     多出:", e) } }
    }
}
