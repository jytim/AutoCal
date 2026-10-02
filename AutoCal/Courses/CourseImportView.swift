import SwiftUI

/// 從課表截圖辨識出的課，確認後存進課表。
struct CourseImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [CourseDraft]
    @State private var termStart: Date
    @State private var termEnd: Date

    init(drafts: [CourseDraft]) {
        _drafts = State(initialValue: drafts)
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        _termStart = State(initialValue: weekStart)
        _termEnd = State(initialValue: cal.date(byAdding: .day, value: 18 * 7 - 1, to: weekStart) ?? weekStart)
    }

    private var selectedCount: Int { drafts.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("學期第一天", selection: $termStart, displayedComponents: .date)
                    DatePicker("學期最後一天", selection: $termEnd, displayedComponents: .date)
                } header: {
                    Text("學期範圍")
                } footer: {
                    Text("每門課會在這段期間內每週重複。課堂只存在 AutoCal 的課表，不會加進行事曆。")
                }

                Section {
                    ForEach($drafts) { $d in
                        HStack(alignment: .top) {
                            Toggle("", isOn: $d.isSelected).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(.headline)
                                Text("週\(Course.weekdayNames[max(0, min(6, d.weekday - 1))]) "
                                     + (d.periodText.map { "\($0) " } ?? "")
                                     + d.timeText
                                     + (d.location.map { " · \($0)" } ?? ""))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("辨識到 \(drafts.count) 堂課，請確認時間")
                } footer: {
                    Text("請對照截圖確認星期和節次。節次換算用台科大的時間表；有錯的話，加入後可以點課堂編輯，或取消勾選。")
                }
            }
            .navigationTitle("匯入課表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入課表（\(selectedCount)）") { save() }
                        .disabled(selectedCount == 0 || termEnd < termStart)
                }
            }
        }
    }

    private func save() {
        let courses: [Course] = drafts.filter(\.isSelected).compactMap { d in
            guard let s = d.startMinute, let e = d.endMinute, e > s else { return nil }
            return Course(name: d.name, weekday: d.weekday, startMinute: s, endMinute: e,
                          location: d.location, termStart: termStart, termEnd: termEnd)
        }
        CourseStore.shared.add(courses)
        dismiss()
    }
}
