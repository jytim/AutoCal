import SwiftUI

/// 設定 → 課堂管理：不靠「課表」分頁也能新增、匯入、編輯、刪除課堂。
/// 課堂資料不論課表分頁有沒有顯示，都會用在衝突偵測、上課提醒與鎖定畫面桌布。
struct CourseManageView: View {
    @ObservedObject private var store = CourseStore.shared
    @StateObject private var add = CourseAddModel()

    var body: some View {
        List {
            if store.courses.isEmpty {
                Section {
                    Text("還沒有課堂，按右上角 ＋ 新增。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(1...7, id: \.self) { day in
                let items = store.courses.filter { $0.weekday == day }
                    .sorted { $0.startMinute < $1.startMinute }
                if !items.isEmpty {
                    Section("週" + Course.weekdayNames[day - 1]) {
                        ForEach(items) { c in
                            Button { add.formTarget = .init(course: c) } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(EventColor.color(for: c)).frame(width: 12, height: 12)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).foregroundStyle(.primary)
                                        Text(c.timeText + (c.location.map { "　\($0)" } ?? ""))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.map { items[$0].id }.forEach { store.delete(id: $0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("課堂管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CourseAddMenu(model: add) } }
        .courseAddFlow(add)
    }
}
