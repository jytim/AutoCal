import Foundation
import EventKit
import SwiftUI

/// 日程頂端的「整天」項目（國定假日、出國這類跨多天的事）。
struct AllDayItem: Identifiable {
    let id: String
    let title: String
    let color: Color
    /// 跨多天時的「第N/共M天」，單日就是 nil。
    let progress: String?
    let location: String?
    let notes: String?
}

/// 單日檢視的資料：當天的行程（含課堂）排成時間軸，整天的項目放在最上面。
@MainActor
final class DayViewModel: ObservableObject {
    @Published var day: Date
    @Published var timed: [TimetableEvent] = []
    @Published var allDay: [AllDayItem] = []
    @Published var accessDenied = false
    /// 這一天所在那一週（週一開頭）的七天，以及其中有行程／課堂的日子（週日期列的小點）。
    @Published var weekDays: [Date] = []
    @Published var markedDays: Set<Date> = []

    /// 時間軸顯示範圍（小時）。
    static let startHour = 6
    static let endHour = 24

    private let store = EKEventStore()
    private let calendar = Calendar.current

    init(day: Date = Date()) {
        self.day = Calendar.current.startOfDay(for: day)
    }

    func select(_ newDay: Date) {
        day = calendar.startOfDay(for: newDay)
        Task { await load() }
    }

    func shift(by days: Int) {
        select(calendar.date(byAdding: .day, value: days, to: day) ?? day)
    }

    func load() async {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        var timedOut: [TimetableEvent] = []
        var allDayOut: [AllDayItem] = []

        // 週日期列：這一週哪幾天有事
        var wcal = calendar
        wcal.firstWeekday = 2
        let weekStart = wcal.dateInterval(of: .weekOfYear, for: dayStart)?.start ?? dayStart
        let weekDaysOut = (0..<7).compactMap { wcal.date(byAdding: .day, value: $0, to: weekStart) }
        var marked: Set<Date> = []

        if (try? await store.requestFullAccessToEvents()) == true {
            accessDenied = false
            if let weekEnd = weekDaysOut.last.flatMap({ calendar.date(byAdding: .day, value: 1, to: $0) }) {
                let wpred = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: nil)
                for e in store.events(matching: wpred) {
                    guard let s = e.startDate, let en = e.endDate else { continue }
                    var d = calendar.startOfDay(for: s)
                    let last = calendar.startOfDay(for: en > s ? en.addingTimeInterval(-1) : en)
                    while d <= last {
                        marked.insert(d)
                        guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                        d = n
                    }
                }
            }
            let pred = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
            for e in store.events(matching: pred) {
                guard let s = e.startDate, let en = e.endDate else { continue }
                let title = e.title ?? "（無標題）"
                if e.isAllDay {
                    let first = calendar.startOfDay(for: s)
                    let lastRef = en > s ? en.addingTimeInterval(-1) : en
                    let last = max(first, calendar.startOfDay(for: lastRef))
                    let total = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
                    let n = (calendar.dateComponents([.day], from: first, to: dayStart).day ?? 0) + 1
                    allDayOut.append(AllDayItem(
                        id: (e.eventIdentifier ?? UUID().uuidString) + "-allday",
                        title: title,
                        color: SubjectColor.color(for: title),
                        progress: total > 1 ? "第\(n)/\(total)天" : nil,
                        location: e.location, notes: e.notes))
                } else {
                    // 跨午夜的行程只畫在這一天的範圍內
                    timedOut.append(TimetableEvent(
                        id: (e.eventIdentifier ?? UUID().uuidString) + "\(s.timeIntervalSince1970)",
                        title: title,
                        start: max(s, dayStart),
                        end: min(en, dayEnd),
                        location: e.location,
                        notes: e.notes,
                        color: EventColor.color(for: e)))
                }
            }
        } else {
            accessDenied = true   // 沒權限時課堂仍照常顯示
        }

        for o in CourseStore.shared.occurrences(on: dayStart) {
            timedOut.append(TimetableEvent(
                id: "course-" + o.id, title: o.course.name,
                start: o.start, end: o.end,
                location: o.course.location, notes: nil,
                color: EventColor.color(for: o.course),
                courseID: o.course.id))
        }

        for d in weekDaysOut where !CourseStore.shared.occurrences(on: d).isEmpty { marked.insert(d) }

        // 連按切換日期時，慢回來的舊結果不能蓋掉新的
        guard calendar.startOfDay(for: day) == dayStart else { return }
        weekDays = weekDaysOut
        markedDays = marked
        timed = timedOut.sorted { $0.start < $1.start }
        allDay = allDayOut.sorted { $0.title < $1.title }
    }
}
