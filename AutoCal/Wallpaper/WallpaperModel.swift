import Foundation
import EventKit
import SwiftUI

/// 桌布上的一個時間塊（行事曆行程或課堂）。
struct WallpaperItem: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let color: Color
    let isCourse: Bool
}

enum WallpaperRow: Identifiable {
    case item(WallpaperItem, isNow: Bool, isFirst: Bool)
    case free(start: Date, end: Date)
    case more(Int)

    var id: String {
        switch self {
        case .item(let i, _, _): return "i" + i.id.uuidString
        case .free(let s, _): return "f\(s.timeIntervalSince1970)"
        case .more(let n): return "m\(n)"
        }
    }
}

struct WallpaperContent {
    var day: Date
    var isToday: Bool
    var generatedAt: Date
    var chips: [String]
    var rows: [WallpaperRow]
    var tomorrow: [WallpaperItem]
    var hasCalendarAccess: Bool
}

/// 把「某一天還剩下什麼」整理成桌布要畫的內容。
@MainActor
enum WallpaperContentBuilder {
    static let freeFromHour = 8
    static let freeToHour = 22
    static let minFreeMinutes = 45

    // 版面高度（pt），要和 WallpaperCanvas 用的一致
    static let bigCardHeight: CGFloat = 78
    static let itemHeight: CGFloat = 54
    static let freeHeight: CGFloat = 26
    static let moreHeight: CGFloat = 18
    static let rowSpacing: CGFloat = 8

    /// - Parameters:
    ///   - day: 要顯示哪一天
    ///   - now: 現在時間；今天會略過已經結束的
    ///   - budget: 列表區可用高度（pt）
    static func build(day: Date, now: Date, budget: CGFloat) -> WallpaperContent {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let isToday = cal.isDate(dayStart, inSameDayAs: now)
        let access = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        CourseStore.shared.reload()   // 課表可能剛在 App 裡改過

        let (all, chips) = items(on: dayStart, access: access)
        let remaining = all.filter { !isToday || $0.end > now }

        // 排出「項目 + 項目之間的空堂」
        var specs: [WallpaperRow] = []
        var cursor = cal.date(bySettingHour: freeFromHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        if isToday { cursor = max(cursor, now) }
        let freeEnd = cal.date(bySettingHour: freeToHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        for (i, it) in remaining.enumerated() {
            if it.start.timeIntervalSince(cursor) >= Double(minFreeMinutes * 60), cursor < freeEnd {
                specs.append(.free(start: cursor, end: min(it.start, freeEnd)))
            }
            specs.append(.item(it, isNow: isToday && it.start <= now, isFirst: i == 0))
            cursor = max(cursor, it.end)
        }

        // 依高度預算裝進去，放不下的收成「還有 N 件」
        var rows: [WallpaperRow] = []
        var used: CGFloat = 0
        for (idx, r) in specs.enumerated() {
            let h = height(of: r)
            if used + h > budget - (moreHeight + rowSpacing) {
                let leftover = specs[idx...].filter { if case .item = $0 { return true } else { return false } }.count
                if case .free = rows.last { rows.removeLast() }
                if leftover > 0 { rows.append(.more(leftover)) }
                break
            }
            rows.append(r)
            used += h + rowSpacing
        }

        let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let tomorrow = Array(items(on: nextDay, access: access).0.prefix(2))

        return WallpaperContent(day: dayStart, isToday: isToday, generatedAt: now,
                                chips: chips, rows: rows, tomorrow: tomorrow,
                                hasCalendarAccess: access)
    }

    static func height(of row: WallpaperRow) -> CGFloat {
        switch row {
        case .item(_, _, let isFirst): return isFirst ? bigCardHeight : itemHeight
        case .free: return freeHeight
        case .more: return moreHeight
        }
    }

    /// 某一天的行程（行事曆 + 課堂）與整天事項的標籤。
    private static func items(on dayStart: Date, access: Bool) -> ([WallpaperItem], [String]) {
        let cal = Calendar.current
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return ([], []) }
        var out: [WallpaperItem] = []
        var chips: [String] = []

        if access {
            let store = EKEventStore()
            let pred = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
            for e in store.events(matching: pred) {
                let title = e.title ?? "（無標題）"
                if e.isAllDay {
                    // 跨多天的整天事項只標「第N/共M天」，不占一列
                    guard let evStart = e.startDate, let evEnd = e.endDate else { continue }
                    let first = cal.startOfDay(for: evStart)
                    let lastRef = evEnd > evStart ? evEnd.addingTimeInterval(-1) : evEnd
                    let last = max(first, cal.startOfDay(for: lastRef))
                    let total = (cal.dateComponents([.day], from: first, to: last).day ?? 0) + 1
                    let n = (cal.dateComponents([.day], from: first, to: dayStart).day ?? 0) + 1
                    chips.append(total > 1 ? "\(title) 第\(n)/\(total)天" : title)
                } else {
                    guard let evStart = e.startDate, let evEnd = e.endDate else { continue }
                    out.append(WallpaperItem(title: title,
                                             start: max(evStart, dayStart),
                                             end: min(evEnd, dayEnd),
                                             location: e.location,
                                             color: EventColor.color(for: e),
                                             isCourse: false))
                }
            }
        }
        for o in CourseStore.shared.occurrences(on: dayStart) {
            out.append(WallpaperItem(title: o.course.name, start: o.start, end: o.end,
                                     location: o.course.location,
                                     color: EventColor.color(for: o.course),
                                     isCourse: true))
        }
        return (out.sorted { $0.start < $1.start }, chips)
    }
}
