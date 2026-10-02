import SwiftUI

/// 主畫面：新增（輸入 / 搜尋）、月曆、課表三個分頁。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("新增", systemImage: "plus.circle") }
            MonthView()
                .tabItem { Label("月曆", systemImage: "calendar") }
            TimetableView()
                .tabItem { Label("課表", systemImage: "calendar.day.timeline.left") }
        }
        // 上課提醒：回到前景、課表有變動時，重排未來三週的通知
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await ClassReminderScheduler.refresh() } }
        }
        .onReceive(CourseStore.shared.$courses) { _ in
            Task { await ClassReminderScheduler.refresh() }
        }
    }
}
