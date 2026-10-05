import Foundation
struct Truth: Codable { let name: String; let weekday: Int; let start: Int; let end: Int }
struct Scenario: Codable { let name: String; let images: [String]; let truth: [Truth] }
let manifest = try! JSONDecoder().decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: "manifest.json")))
// 只看「沒標題」的那張圖（g*_b、g3_b）：同一欄的方塊是不是同一天、不同天是不是不同欄
for sc in manifest {
    for im in sc.images where !im.hasSuffix("_a.jpg") || sc.images.count == 1 {
        var ds = try! JSONDecoder().decode([CourseDraft].self, from: Data(contentsOf: URL(fileURLWithPath: "raw_" + im.replacingOccurrences(of: ".jpg", with: ".json"))))
        guard ds.contains(where: { !$0.hasHeader }) else { continue }
        for k in ds.indices { ds[k].sourceIndex = 0; ds[k].weekday = 0; ds[k].hasHeader = false }   // 當成唯一一張沒標題的圖
        let res = CourseDraft.assigningWeekdays(ds)
        // 對答案：每個方塊找到真實星期
        var pairs: [(group: Int, day: Int)] = []
        for d in res {
            guard let g = d.columnGroup, let s = d.startMinute, let e = d.endMinute,
                  let t = sc.truth.first(where: { CourseDraft.namesMatch($0.name, d.name) && $0.start == s && $0.end == e }) else { continue }
            pairs.append((g, t.weekday))
        }
        let byGroup = Dictionary(grouping: pairs, by: \.group).mapValues { Set($0.map(\.day)) }
        let pure = byGroup.values.allSatisfy { $0.count == 1 }
        let byDay = Dictionary(grouping: pairs, by: \.day).mapValues { Set($0.map(\.group)) }
        let split = byDay.values.allSatisfy { $0.count == 1 }
        let ordered = byGroup.sorted { $0.key < $1.key }.compactMap { $0.value.first }
        let monotone = zip(ordered, ordered.dropFirst()).allSatisfy { $0 < $1 }
        print("\(im): 分成 \(byGroup.count) 欄 / 真實 \(byDay.count) 天; 同欄同一天=\(pure) 同一天沒被拆開=\(split) 由左到右遞增=\(monotone) (\(pairs.count)/\(res.count) 筆有對到答案)")
    }
}
