import Foundation
import UserNotifications

/// 讓通知在 AutoCal 開著的時候也會跳出橫幅（預設前景不顯示）。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum ClassReminderKeys {
    static let enabled = "notify.classEnabled"
    static let lead = "notify.classLead"
}

/// 上課前提醒。
///
/// 為什麼不用「每週重複」的通知：重複通知不知道學期什麼時候結束，也沒辦法跳過停課日。
/// 所以改成往後排約三週的個別通知，每次打開 App 或改課表就整批重排。
/// iOS 同時最多只留 64 則待發通知，這裡最多排 60 則。
@MainActor
enum ClassReminderScheduler {
    static let idPrefix = "course-"
    static let windowDays = 21
    static let maxPending = 60

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: ClassReminderKeys.enabled) }
    static var leadMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: ClassReminderKeys.lead)
        return v > 0 ? v : 10
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return s == .authorized || s == .provisional || s == .ephemeral
    }

    /// 重排會在好幾個時機被呼叫（打開開關、回到前景、課表變動…），
    /// 如果同時跑，後一個會把前一個排到一半的清掉，結果少了好幾則。
    /// 所以一律排隊，一次只跑一個。
    private static var queue: Task<Void, Never>?

    /// 依目前的課表重排未來幾週的提醒。
    static func refresh() async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await performRefresh()
        }
        queue = task
        await task.value
    }

    private static func performRefresh() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard isEnabled, await isAuthorized() else { return }

        CourseStore.shared.reload()
        let cal = Calendar.current
        let now = Date()
        let lead = leadMinutes
        let today = cal.startOfDay(for: now)

        var upcoming: [(fire: Date, occ: CourseOccurrence)] = []
        for d in 0..<windowDays {
            guard let day = cal.date(byAdding: .day, value: d, to: today) else { continue }
            for o in CourseStore.shared.occurrences(on: day) {
                let fire = o.start.addingTimeInterval(-TimeInterval(lead * 60))
                if fire > now { upcoming.append((fire, o)) }
            }
        }
        upcoming.sort { $0.fire < $1.fire }

        let hm = DateFormatter()
        hm.dateFormat = "HH:mm"
        for item in upcoming.prefix(maxPending) {
            let content = UNMutableNotificationContent()
            content.title = "\(lead) 分鐘後上課：\(item.occ.course.name)"
            let time = "\(hm.string(from: item.occ.start))–\(hm.string(from: item.occ.end))"
            content.body = [time, item.occ.course.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: idPrefix + item.occ.id,
                                                        content: content, trigger: trigger))
        }
    }

    struct Summary {
        var count: Int
        var nextTitle: String?
        var nextFire: Date?
    }

    /// 目前排了幾則、下一則是什麼（給設定頁顯示，也讓使用者能核對）。
    static func summary() async -> Summary {
        await queue?.value   // 等排程跑完再讀，才不會讀到排到一半的結果
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(idPrefix) }
        let next = pending
            .compactMap { r -> (String, Date)? in
                guard let t = r.trigger as? UNCalendarNotificationTrigger,
                      let d = t.nextTriggerDate() else { return nil }
                return (r.content.title, d)
            }
            .min { $0.1 < $1.1 }
        return Summary(count: pending.count, nextTitle: next?.0, nextFire: next?.1)
    }

    /// 5 秒後響一則測試通知，確認權限和橫幅都正常。
    static func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "記吧 測試通知"
        content.body = "看到這則，代表上課提醒會正常響。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "autocal-test", content: content, trigger: trigger))
    }
}
