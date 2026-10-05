import Foundation
import EventKit

/// 記吧加入過的行程與待辦的紀錄：一次加好幾筆結果不對時，可以整批或單筆刪掉。
/// 只刪「記吧自己建的」那幾筆，不會動到使用者原本的行事曆。
struct AddedRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var isEvent: Bool
    var title: String
    var start: Date?
    /// 行事曆：eventIdentifier；提醒事項：calendarItemIdentifier。
    var itemID: String
}

struct AddBatch: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var records: [AddedRecord]
}

enum AddHistory {
    private static let key = "add.history"
    private static let keepDays: TimeInterval = 30 * 86400

    static func load() -> [AddBatch] {
        guard let data = AppConfig.sharedDefaults.data(forKey: key),
              let all = try? JSONDecoder().decode([AddBatch].self, from: data) else { return [] }
        return all.filter { Date().timeIntervalSince($0.date) < keepDays && !$0.records.isEmpty }
    }

    private static func save(_ batches: [AddBatch]) {
        if let data = try? JSONEncoder().encode(Array(batches.prefix(100))) {
            AppConfig.sharedDefaults.set(data, forKey: key)
        }
    }

    static func add(_ batch: AddBatch) {
        guard !batch.records.isEmpty else { return }
        save([batch] + load())
    }

    private static func remove(recordIDs: Set<UUID>) {
        save(load().compactMap { b in
            var b = b; b.records.removeAll { recordIDs.contains($0.id) }
            return b.records.isEmpty ? nil : b
        })
    }

    struct UndoResult { var removed = 0; var alreadyGone = 0; var failed = 0 }

    /// 刪掉指定的幾筆（行事曆與提醒事項）。找不到的（使用者已經自己刪了）算「已不存在」，不當錯誤。
    @MainActor
    static func undo(_ records: [AddedRecord]) async -> UndoResult {
        let store = EKEventStore()
        var res = UndoResult()
        var done: Set<UUID> = []
        if records.contains(where: \.isEvent) { _ = try? await store.requestFullAccessToEvents() }
        if records.contains(where: { !$0.isEvent }) { _ = try? await store.requestFullAccessToReminders() }
        for r in records {
            do {
                if r.isEvent {
                    if let e = findEvent(r, in: store) {
                        try store.remove(e, span: .thisEvent, commit: true); res.removed += 1
                    } else { res.alreadyGone += 1 }
                } else {
                    if let rem = store.calendarItem(withIdentifier: r.itemID) as? EKReminder {
                        try store.remove(rem, commit: true); res.removed += 1
                    } else { res.alreadyGone += 1 }
                }
                done.insert(r.id)
            } catch { res.failed += 1 }
        }
        remove(recordIDs: done)
        return res
    }

    /// 先用識別碼找；同步後識別碼偶爾會變，找不到就用「標題 + 開始時間」在當天找。
    private static func findEvent(_ r: AddedRecord, in store: EKEventStore) -> EKEvent? {
        if let e = store.event(withIdentifier: r.itemID) { return e }
        guard let s = r.start else { return nil }
        let pred = store.predicateForEvents(withStart: s.addingTimeInterval(-60), end: s.addingTimeInterval(86400), calendars: nil)
        return store.events(matching: pred).first { $0.title == r.title && abs($0.startDate.timeIntervalSince(s)) < 60 }
    }

    static func summary(_ r: UndoResult) -> String {
        var t = "已復原 \(r.removed) 項"
        if r.alreadyGone > 0 { t += "（\(r.alreadyGone) 項已不在行事曆裡）" }
        if r.failed > 0 { t += "，\(r.failed) 項刪除失敗" }
        return t
    }
}
