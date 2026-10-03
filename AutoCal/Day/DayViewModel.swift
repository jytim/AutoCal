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

        if (try? await store.requestFullAccessToEvents()) == true {
            accessDenied = false
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

        // 連按切換日期時，慢回來的舊結果不能蓋掉新的
        guard calendar.startOfDay(for: day) == dayStart else { return }
        timed = timedOut.sorted { $0.start < $1.start }
        allDay = allDayOut.sorted { $0.title < $1.title }
    }
}
