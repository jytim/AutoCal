import Foundation
import EventKit
import SwiftUI

/// 月曆上的一筆行程。
struct MonthEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let color: Color
    /// 涵蓋的第一天與最後一天（都是當天 00:00）。
    let firstDay: Date
    let lastDay: Date

    var isMultiDay: Bool { firstDay != lastDay }
}

/// 跨多天行程在某一天的狀態（第幾天、是不是第一天/最後一天）。
struct TripSpan: Identifiable {
    let event: MonthEvent
    let dayNumber: Int
    let totalDays: Int
    var id: String { event.id }
    var isStart: Bool { dayNumber == 1 }
    var isEnd: Bool { dayNumber == totalDays }
}

@MainActor
final class MonthViewModel: ObservableObject {
    @Published var monthStart: Date
    @Published var events: [MonthEvent] = []
    @Published var accessDenied = false

    private let store = EKEventStore()
    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // 週一開頭
        return c
    }

    init() {
        let c = Calendar.current
        monthStart = c.date(from: c.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    // MARK: - 日期格子

    /// 這個月畫面上所有的天（含前後月份補滿的週），一定是 7 的倍數。
    var weeks: [[Date]] {
        guard let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart),
              let gridStart = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start,
              let lastWeek = cal.dateInterval(of: .weekOfYear, for: monthEnd)
        else { return [] }
        var days: [Date] = []
        var d = gridStart
        while d < lastWeek.end {
            days.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? lastWeek.end
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    func isInMonth(_ day: Date) -> Bool {
        cal.isDate(day, equalTo: monthStart, toGranularity: .month)
    }

    func shiftMonth(by months: Int) {
        monthStart = cal.date(byAdding: .month, value: months, to: monthStart) ?? monthStart
        Task { await load() }
    }

    /// 切到包含指定日期的那個月。
    func goTo(date: Date) {
        monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? monthStart
        Task { await load() }
    }

    func goToThisMonth() {
        monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? monthStart
        Task { await load() }
    }

    // MARK: - 讀取

    func load() async {
        guard (try? await store.requestFullAccessToEvents()) == true else {
            accessDenied = true
            return
        }
        accessDenied = false
        guard let first = weeks.first?.first, let lastDay = weeks.last?.last,
              let rangeEnd = cal.date(byAdding: .day, value: 1, to: lastDay) else { return }

        let pred = store.predicateForEvents(withStart: first, end: rangeEnd, calendars: nil)
        events = store.events(matching: pred).map { e in
            let (firstDay, lastDay) = coveredDays(start: e.startDate, end: e.endDate)
            return MonthEvent(
                id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                title: e.title ?? "（無標題）",
                start: e.startDate,
                end: e.endDate,
                isAllDay: e.isAllDay,
                location: e.location,
                notes: e.notes,
                color: EventColor.color(for: e),
                firstDay: firstDay,
                lastDay: lastDay)
        }
        .sorted { $0.start < $1.start }
    }

    /// 行程涵蓋的第一天與最後一天。結束時間剛好是午夜（或整天行程的結束）要往前算一秒，
    /// 才不會多算一天。
    private func coveredDays(start: Date, end: Date) -> (Date, Date) {
        let first = cal.startOfDay(for: start)
        let ref = end > start ? end.addingTimeInterval(-1) : end
        return (first, max(first, cal.startOfDay(for: ref)))
    }

    // MARK: - 每格內容

    /// 當天正在進行的跨多天行程。
    func spans(on day: Date) -> [TripSpan] {
        let d = cal.startOfDay(for: day)
        return events.filter { $0.isMultiDay && $0.firstDay <= d && d <= $0.lastDay }.map { e in
            let n = (cal.dateComponents([.day], from: e.firstDay, to: d).day ?? 0) + 1
            let total = (cal.dateComponents([.day], from: e.firstDay, to: e.lastDay).day ?? 0) + 1
            return TripSpan(event: e, dayNumber: n, totalDays: total)
        }
    }

    /// 當天開始的單日行程：整天的在前，其餘依時間排序。
    func singles(on day: Date) -> [MonthEvent] {
        let d = cal.startOfDay(for: day)
        return events.filter { !$0.isMultiDay && $0.firstDay == d }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }
}
