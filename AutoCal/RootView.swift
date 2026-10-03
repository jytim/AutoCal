import SwiftUI

/// 主畫面：新增、月曆、日程、課表四個分頁。
struct RootView: View {
    enum Tab: Hashable { case add, month, day, timetable }

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .add
    @StateObject private var dayVM = DayViewModel()

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("新增", systemImage: "plus.circle") }
                .tag(Tab.add)
            MonthView(onSelectDay: { day in
                dayVM.select(day)      // 月曆點某一天 → 跳到日程看那一天
                tab = .day
            })
                .tabItem { Label("月曆", systemImage: "calendar") }
                .tag(Tab.month)
            DayView(vm: dayVM)
                .tabItem { Label("日程", systemImage: "list.bullet.below.rectangle") }
                .tag(Tab.day)
            TimetableView()
                .tabItem { Label("課表", systemImage: "calendar.day.timeline.left") }
                .tag(Tab.timetable)
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
