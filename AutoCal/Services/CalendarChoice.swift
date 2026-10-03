import EventKit
import SwiftUI

/// 確認卡片上「寫進哪個行事曆」的選項（只列可寫入的行事曆）。
struct CalendarChoice: Identifiable {
    let id: String
    let title: String
    let color: Color
    let isDefault: Bool

    /// 沒有行事曆權限時回傳空陣列（卡片就不顯示選單，照系統預設寫入）。
    static func load() -> [CalendarChoice] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
        let defID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title,
                                  color: Color(cgColor: $0.cgColor), isDefault: $0.calendarIdentifier == defID) }
    }
}
