import SwiftUI

/// 設定頁裡的「課前提醒」區塊。
struct ClassReminderSection: View {
    @AppStorage(ClassReminderKeys.enabled) private var enabled = false
    @AppStorage(ClassReminderKeys.lead) private var lead = 10
    @State private var summaryText = ""
    @State private var denied = false
    @State private var testSent = false

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d (E) HH:mm"
        return f
    }()

    var body: some View {
        Section {
            Toggle("上課前提醒", isOn: $enabled)
            if enabled {
                Picker("提前", selection: $lead) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) 分鐘").tag($0) }
                }
                if !summaryText.isEmpty {
                    Text(summaryText).font(.footnote).foregroundStyle(.secondary)
                }
                Button(testSent ? "已排定，5 秒後會響" : "傳一則測試通知") {
                    Task {
                        await ClassReminderScheduler.sendTest()
                        testSent = true
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        testSent = false
                    }
                }
                .disabled(testSent)
            }
            if denied {
                Text("通知權限沒有開，請到 iOS「設定」→「通知」→ AutoCal 開啟。")
                    .font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("課前提醒")
        } footer: {
            Text("只排未來約三週，打開 App 或改課表時會重排。")
        }
        .onChange(of: enabled) { _, on in Task { await toggled(on) } }
        .onChange(of: lead) { _, _ in Task { await ClassReminderScheduler.refresh(); await updateSummary() } }
        .task { await updateSummary() }
    }

    private func toggled(_ on: Bool) async {
        if on {
            guard await ClassReminderScheduler.requestPermission() else {
                denied = true
                enabled = false
                return
            }
            denied = false
        }
        await ClassReminderScheduler.refresh()
        await updateSummary()
    }

    private func updateSummary() async {
        guard enabled else { summaryText = ""; return }
        let s = await ClassReminderScheduler.summary()
        if s.count == 0 {
            summaryText = "目前沒有要提醒的課（還沒有課堂，或未來三週都沒課）。"
        } else if let t = s.nextTitle, let d = s.nextFire {
            summaryText = "已排定 \(s.count) 則。下一則：\(Self.df.string(from: d))「\(t)」"
        } else {
            summaryText = "已排定 \(s.count) 則。"
        }
    }
}
