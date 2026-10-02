import Foundation
import EventKit

/// 把 ParsedItem 寫進 iOS 內建行事曆 / 提醒事項。
@MainActor
final class EventStoreWriter {
    private let store = EKEventStore()

    struct WriteResult {
        var events = 0
        var reminders = 0
        var failures: [String] = []
    }

    /// 依需要請求權限並寫入。回傳寫入結果。
    func write(_ items: [ParsedItem]) async throws -> WriteResult {
        let needsCalendar = items.contains { $0.type == .event && $0.isSelected }
        let needsReminder = items.contains { $0.type == .todo && $0.isSelected }

        if needsCalendar {
            guard try await store.requestFullAccessToEvents() else {
                throw NSError(domain: "AutoCal", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "沒有行事曆權限"])
            }
        }
        if needsReminder {
            guard try await store.requestFullAccessToReminders() else {
                throw NSError(domain: "AutoCal", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "沒有提醒事項權限"])
            }
        }

        var result = WriteResult()
        for item in items where item.isSelected {
            do {
                switch item.type {
                case .event:
                    try writeEvent(item)
                    result.events += 1
                case .todo:
                    try writeReminder(item)
                    result.reminders += 1
                }
            } catch {
                result.failures.append("\(item.title)：\(error.localizedDescription)")
            }
        }
        return result
    }

    private func writeEvent(_ item: ParsedItem) throws {
        let event = EKEvent(eventStore: store)
        event.title = item.title
        event.location = item.location
        event.isAllDay = item.allDay
        event.notes = item.calendarNote

        let start = item.start ?? Date()
        event.startDate = start
        // 沒給結束時間就補一小時（整天行程補當天）
        event.endDate = item.end ?? (item.allDay
            ? Calendar.current.date(byAdding: .day, value: 1, to: start)
            : Calendar.current.date(byAdding: .hour, value: 1, to: start)) ?? start
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }

    private func writeReminder(_ item: ParsedItem) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = item.title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = item.start ?? item.end {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
        }
        try store.save(reminder, commit: true)
    }
}
