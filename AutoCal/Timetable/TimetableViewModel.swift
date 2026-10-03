import Foundation
import EventKit
import SwiftUI

/// 課表上的一個時間塊：Apple 行事曆的一筆行程，或 AutoCal 課表裡的一堂課。
struct TimetableEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let notes: String?
    let color: Color
    /// 不是 nil 代表這是一堂課（不在 Apple 行事曆裡）。
    var courseID: UUID? = nil
    var isCourse: Bool { courseID != nil }
}

/// 一天裡某段沒有任何行程的空檔。
struct FreeSlot: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

@MainActor
final class TimetableViewModel: ObservableObject {
    @Published var weekStart: Date
    @Published var events: [TimetableEvent] = []
    @Published var accessDenied = false

    /// 課表顯示的時間範圍（小時）。
    static let startHour = 7
    static let endHour = 23
    /// 空堂的判定範圍與最短長度。
    static let freeFromHour = 8
    static let freeToHour = 18
    static let minFreeMinutes = 45

    private let store = EKEventStore()
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // 週一開頭
        return c
    }

    init() {
        weekStart = Self.defaultWeekStart()
    }

    /// 預設顯示的那一週的週一。週六、週日改看「下一週」（週一到週五已經過了，週末最想看的是下週的課）。
    static func defaultWeekStart(now: Date = Date()) -> Date {
        var c = Calendar.current
        c.firstWeekday = 2
        let monday = c.dateInterval(of: .weekOfYear, for: now)?.start ?? c.startOfDay(for: now)
        let wd = c.component(.weekday, from: now)           // 1 = 週日、7 = 週六
        if wd == 1 || wd == 7 { return c.date(byAdding: .day, value: 7, to: monday) ?? monday }
        return monday
    }

    /// 本週的七天（週一～週日）。
    var days: [Date] {
        (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    func shiftWeek(by weeks: Int) {
        weekStart = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart
        Task { await load() }
    }

    func goToThisWeek() {
        weekStart = Self.defaultWeekStart()
        Task { await load() }
    }

    func load() async {
        var fromCalendar: [TimetableEvent] = []
        if (try? await store.requestFullAccessToEvents()) == true {
            accessDenied = false
            if let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) {
                let pred = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: nil)
                fromCalendar = store.events(matching: pred)
                    .filter { !$0.isAllDay }
                    .map { e in
                        TimetableEvent(
                            id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                            title: e.title ?? "（無標題）",
                            start: e.startDate,
                            end: e.endDate,
                            location: e.location,
                            notes: e.notes,
                            color: SubjectColor.color(for: e.title ?? ""))
                    }
            }
        } else {
            accessDenied = true   // 沒有行事曆權限時，課堂仍然照常顯示
        }

        // 課堂來自 AutoCal 自己的課表，不在 Apple 行事曆裡
        let fromCourses = days.flatMap { CourseStore.shared.occurrences(on: $0) }.map { o in
            TimetableEvent(id: "course-" + o.id,
                           title: o.course.name,
                           start: o.start,
                           end: o.end,
                           location: o.course.location,
                           notes: nil,
                           color: SubjectColor.color(for: o.course.name),
                           courseID: o.course.id)
        }
        events = (fromCalendar + fromCourses).sorted { $0.start < $1.start }
    }

    // MARK: - 排版

    func events(on day: Date) -> [TimetableEvent] {
        events.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// 撞時段的行程分成並排的「車道」，回傳每筆的 (車道編號, 該群組車道總數)。
    nonisolated static func lanes(for dayEvents: [TimetableEvent]) -> [String: (lane: Int, count: Int)] {
        var result: [String: (Int, Int)] = [:]
        var cluster: [TimetableEvent] = []
        var clusterEnd = Date.distantPast

        func flush() {
            var laneEnds: [Date] = []
            var assigned: [(TimetableEvent, Int)] = []
            for e in cluster {
                if let i = laneEnds.firstIndex(where: { $0 <= e.start }) {
                    laneEnds[i] = e.end
                    assigned.append((e, i))
                } else {
                    laneEnds.append(e.end)
                    assigned.append((e, laneEnds.count - 1))
                }
            }
            for (e, lane) in assigned { result[e.id] = (lane, max(laneEnds.count, 1)) }
            cluster = []
        }

        for e in dayEvents.sorted(by: { $0.start < $1.start }) {
            if !cluster.isEmpty && e.start >= clusterEnd { flush(); clusterEnd = .distantPast }
            cluster.append(e)
            clusterEnd = max(clusterEnd, e.end)
        }
        if !cluster.isEmpty { flush() }
        return result.mapValues { (lane: $0.0, count: $0.1) }
    }

    /// 這一天（八點到二十二點之間）的空檔，只回傳夠長的。
    func freeSlots(on day: Date) -> [FreeSlot] {
        guard let from = calendar.date(bySettingHour: Self.freeFromHour, minute: 0, second: 0, of: day),
              let to = calendar.date(bySettingHour: Self.freeToHour, minute: 0, second: 0, of: day)
        else { return [] }

        // 合併重疊的忙碌區間
        let busy = events(on: day)
            .map { (max($0.start, from), min($0.end, to)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for b in busy {
            if let last = merged.last, b.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, b.1)
            } else {
                merged.append(b)
            }
        }

        var slots: [FreeSlot] = []
        var cursor = from
        for b in merged {
            if b.0.timeIntervalSince(cursor) >= Double(Self.minFreeMinutes * 60) {
                slots.append(FreeSlot(start: cursor, end: b.0))
            }
            cursor = max(cursor, b.1)
        }
        if to.timeIntervalSince(cursor) >= Double(Self.minFreeMinutes * 60) {
            slots.append(FreeSlot(start: cursor, end: to))
        }
        return slots
    }

    func isWeekday(_ day: Date) -> Bool {
        let w = calendar.component(.weekday, from: day)
        return (2...6).contains(w)
    }
}
