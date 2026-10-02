import Foundation
import EventKit

/// 寫入前檢查新行程和既有行程（以及同一批新行程彼此）是否撞時段，
/// 並請模型判斷能否同時進行、幫忙找當天最近的空檔。
@MainActor
final class ConflictChecker {
    private let store = EKEventStore()
    private let llm = LLMClient()

    /// 為每筆有衝突的行程填入 conflicts / suggestedStart / aiNote / resolution（預設採用 AI 建議）。
    func annotate(_ items: [ParsedItem]) async -> [ParsedItem] {
        guard items.contains(where: Self.isTimedEvent) else { return items }
        // 讀取既有行程需要行事曆權限；被拒就略過檢查，不影響原本流程。
        guard (try? await store.requestFullAccessToEvents()) == true else { return items }

        var result = items
        for i in result.indices {
            result[i].conflicts = []
            result[i].suggestedStart = nil
            result[i].aiNote = nil
            result[i].resolution = .none

            guard Self.isTimedEvent(result[i]), let iv = Self.interval(of: result[i]) else { continue }
            let (start, end) = iv

            var conflicts = existingEvents(from: start, to: end).map {
                ParsedItem.ConflictInfo(title: $0.title ?? "（無標題）", start: $0.startDate, end: $0.endDate)
            }
            // 同一批新行程裡，排在前面、且仍會加入的那些
            for j in result.indices where j < i && result[j].isSelected && result[j].resolution != .skip {
                guard Self.isTimedEvent(result[j]), let other = Self.interval(of: result[j]),
                      other.0 < end, start < other.1 else { continue }
                conflicts.append(.init(title: result[j].title + "（這次新增）", start: other.0, end: other.1))
            }
            guard !conflicts.isEmpty else { continue }

            result[i].conflicts = conflicts
            result[i].suggestedStart = freeSlot(for: i, in: result, start: start,
                                                duration: end.timeIntervalSince(start))

            if let verdict = try? await llm.judgeConcurrency(item: result[i], conflicts: conflicts) {
                result[i].aiNote = verdict.reason
                if verdict.canOverlap {
                    result[i].resolution = .overlap
                } else {
                    // 不能同時做：有空檔就建議移過去；沒有就先維持原時間，讓使用者自己決定
                    result[i].resolution = result[i].suggestedStart != nil ? .move : .overlap
                }
            } else {
                result[i].resolution = .overlap
            }
            if result[i].suggestedStart == nil {
                let note = "當天 23:00 前找不到同樣長度的空檔。"
                result[i].aiNote = [result[i].aiNote, note].compactMap { $0 }.joined(separator: " ")
            }
        }
        return result
    }

    /// 依使用者在卡片上的選擇調整項目：不加入的取消勾選、改時間的套用建議時段。
    nonisolated static func applyResolutions(_ items: [ParsedItem]) -> [ParsedItem] {
        items.map { item in
            var it = item
            switch it.resolution {
            case .skip:
                it.isSelected = false
            case .move:
                if let newStart = it.suggestedStart, let iv = interval(of: it) {
                    it.start = newStart
                    it.end = newStart.addingTimeInterval(iv.1.timeIntervalSince(iv.0))
                }
            case .none, .overlap:
                break
            }
            return it
        }
    }

    // MARK: - 內部

    nonisolated private static func isTimedEvent(_ item: ParsedItem) -> Bool {
        item.type == .event && !item.allDay && item.start != nil
    }

    /// 行程的時間區間；沒有結束時間就當一小時（和寫入時的預設一致）。
    nonisolated private static func interval(of item: ParsedItem) -> (Date, Date)? {
        guard let s = item.start else { return nil }
        return (s, item.end ?? s.addingTimeInterval(3600))
    }

    /// 和區間重疊的既有行程（整天的行程如假日不算衝突）。
    private func existingEvents(from start: Date, to end: Date) -> [EKEvent] {
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred).filter {
            !$0.isAllDay && $0.startDate < end && start < $0.endDate
        }
    }

    /// 從原時間往後、每 15 分鐘找一次，回傳當天 23:00 前第一個放得下的空檔。
    private func freeSlot(for index: Int, in items: [ParsedItem],
                          start: Date, duration: TimeInterval) -> Date? {
        let cal = Calendar.current
        guard let dayEnd = cal.date(bySettingHour: 23, minute: 0, second: 0, of: start) else { return nil }

        var busy = existingEvents(from: cal.startOfDay(for: start), to: dayEnd)
            .map { ($0.startDate!, $0.endDate!) }
        for (j, other) in items.enumerated()
        where j != index && other.isSelected && other.resolution != .skip && Self.isTimedEvent(other) {
            if let iv = Self.interval(of: other) { busy.append(iv) }
        }

        var candidate = start.addingTimeInterval(15 * 60)
        while candidate.addingTimeInterval(duration) <= dayEnd {
            let candEnd = candidate.addingTimeInterval(duration)
            if !busy.contains(where: { $0.0 < candEnd && candidate < $0.1 }) {
                return candidate
            }
            candidate = candidate.addingTimeInterval(15 * 60)
        }
        return nil
    }
}
