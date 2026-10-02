import SwiftUI

/// 主畫面：新增（輸入 / 搜尋）、月曆、課表三個分頁。
struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("新增", systemImage: "plus.circle") }
            MonthView()
                .tabItem { Label("月曆", systemImage: "calendar") }
            TimetableView()
                .tabItem { Label("課表", systemImage: "calendar.day.timeline.left") }
        }
    }
}
