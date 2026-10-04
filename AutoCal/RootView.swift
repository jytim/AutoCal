import SwiftUI

/// 主畫面：新增、行事曆（日／週／月）兩個分頁。
struct RootView: View {
    enum Tab: Hashable { case add, calendar }

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .add

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("新增", systemImage: "plus.circle") }
                .tag(Tab.add)
            CalendarContainerView()
                .tabItem { Label("行事曆", systemImage: "calendar") }
                .tag(Tab.calendar)
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
