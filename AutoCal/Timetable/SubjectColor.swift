import SwiftUI

/// 科目顏色：同一個科目（用標題判斷）永遠是同一個顏色，
/// 第一次出現時才分配，分配結果存在手機上，之後不再變。
enum SubjectColor {
    /// 白字看得清楚的中深色，彼此差異大。
    private static let palette: [Color] = [
        Color(red: 0.23, green: 0.51, blue: 0.96),  // 藍
        Color(red: 0.94, green: 0.27, blue: 0.27),  // 紅
        Color(red: 0.55, green: 0.36, blue: 0.96),  // 紫
        Color(red: 0.98, green: 0.45, blue: 0.09),  // 橘
        Color(red: 0.93, green: 0.28, blue: 0.60),  // 粉
        Color(red: 0.08, green: 0.72, blue: 0.65),  // 青綠
        Color(red: 0.39, green: 0.40, blue: 0.95),  // 靛
        Color(red: 0.85, green: 0.47, blue: 0.02),  // 琥珀
        Color(red: 0.02, green: 0.71, blue: 0.83),  // 青
        Color(red: 0.66, green: 0.33, blue: 0.97),  // 亮紫
        Color(red: 0.63, green: 0.38, blue: 0.07),  // 棕
        Color(red: 0.39, green: 0.45, blue: 0.55)   // 灰藍
    ]

    private static let key = "subject.colorIndex"

    static func color(for title: String) -> Color {
        let name = normalize(title)
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        if let i = map[name] { return palette[i % palette.count] }

        // 第一次看到這個科目：挑目前還沒被用掉的顏色，用光了才重複使用
        let used = Set(map.values.map { $0 % palette.count })
        let index = (0..<palette.count).first(where: { !used.contains($0) })
            ?? (map.count % palette.count)
        map[name] = index
        UserDefaults.standard.set(map, forKey: key)
        return palette[index]
    }

    private static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
