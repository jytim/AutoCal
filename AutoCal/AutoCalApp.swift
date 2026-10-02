import SwiftUI
import UserNotifications

@main
struct AutoCalApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
