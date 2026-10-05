import SwiftUI

/// 從課表截圖辨識出的課，確認後存進課表。
struct CourseImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [CourseDraft]
    @State private var termStart: Date
    @State private var termEnd: Date

    let sourceCount: Int
    let rawCount: Int
    let failures: [String]

    init(drafts: [CourseDraft], sourceCount: Int = 1, rawCount: Int = 0, failures: [String] = []) {
        self.sourceCount = sourceCount
        self.rawCount = rawCount
        self.failures = failures
        _drafts = State(initialValue: drafts)
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        _termStart = State(initialValue: weekStart)
        _termEnd = State(initialValue: cal.date(byAdding: .day, value: 18 * 7 - 1, to: weekStart) ?? weekStart)
    }

    private var selectedCount: Int { drafts.filter(\.isSelected).count }
    /// 沒標題的截圖：同一欄的課 = 同一天。依 App 分出的「欄」分組（同一張截圖、同一欄），
    /// 每一欄一個星期選單，改一次整欄一起換。
    private struct ColumnKey: Hashable { let source: Int; let group: Int }
    private func isPending(_ d: CourseDraft) -> Bool {
        d.isSelected && d.columnGroup != nil && (d.weekday == 0 || d.weekdayGuessed)
    }
    private var pendingColumns: [(key: ColumnKey, names: [String], weekday: Int)] {
        var order: [ColumnKey] = []
        var members: [ColumnKey: [CourseDraft]] = [:]
        for d in drafts where isPending(d) {
            let k = ColumnKey(source: d.sourceIndex, group: d.columnGroup!)
            if members[k] == nil { order.append(k) }
            members[k, default: []].append(d)
        }
        return order.sorted { ($0.source, $0.group) < ($1.source, $1.group) }.map { k in
            let ds = members[k] ?? []
            let days = Set(ds.map(\.weekday))
            return (k, ds.map(\.name), days.count == 1 ? (days.first ?? 0) : 0)
        }
    }

    private func setWeekday(_ w: Int, for key: ColumnKey) {
        guard w != 0 else { return }
        for i in drafts.indices where drafts[i].sourceIndex == key.source
            && drafts[i].columnGroup == key.group && isPending(drafts[i]) {
            drafts[i].weekday = w
            drafts[i].weekdayGuessed = false      // 使用者確認過了
        }
    }

    private var guessedCount: Int { drafts.filter { $0.isSelected && $0.weekday != 0 && $0.weekdayGuessed }.count }
    private var hasUnknownWeekday: Bool { drafts.contains { $0.isSelected && ($0.weekday == 0 || $0.weekdayGuessed) } }

    private var headerText: String {
        var t = "辨識到 \(drafts.count) 堂課，請確認時間"
        if sourceCount > 1 {
            t = "從 \(sourceCount) 張截圖辨識到 \(drafts.count) 堂課"
            if rawCount > drafts.count { t += "（已合併 \(rawCount - drafts.count) 筆重複或被截斷的）" }
        }
        return t
    }

    var body: some View {
        NavigationStack {
            List {
                if !failures.isEmpty {
                    Section("有幾張沒辨識成功") {
                        ForEach(failures, id: \.self) { Text($0).font(.footnote).foregroundStyle(.red) }
                    }
                }
                Section {
                    DatePicker("學期第一天", selection: $termStart, displayedComponents: .date)
                    DatePicker("學期最後一天", selection: $termEnd, displayedComponents: .date)
                } header: {
                    Text("學期範圍")
                }

                if !pendingColumns.isEmpty {
                    Section {
                        ForEach(pendingColumns, id: \.key) { col in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("同一天的課").font(.footnote.bold())
                                    Text(col.names.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("星期", selection: Binding(get: { col.weekday },
                                                                 set: { setWeekday($0, for: col.key) })) {
                                    if col.weekday == 0 { Text("請選擇").tag(0) }
                                    ForEach(1...7, id: \.self) { Text("週" + Course.weekdayNames[$0 - 1]).tag($0) }
                                }
                                .pickerStyle(.menu).labelsHidden()
                                .tint(col.weekday == 0 ? .red : .orange)
                            }
                        }
                    } header: {
                        Text("每一欄的星期（最左邊是週一）")
                }
                }

                if guessedCount > 0 {
                    Section {
                        Button {
                            for i in drafts.indices where drafts[i].weekday != 0 { drafts[i].weekdayGuessed = false }
                        } label: {
                            Label("對照截圖後，全部確認（\(guessedCount)）", systemImage: "checkmark.seal")
                        }
                    } footer: {
                        Text("星期是依欄位推算的，請對照截圖看一眼。")
                    }
                }

                Section {
                    ForEach($drafts) { $d in
                        HStack(alignment: .top) {
                            Toggle("", isOn: $d.isSelected).labelsHidden()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.name).font(.headline)
                                Text((d.periodText.map { "\($0) " } ?? "")
                                     + d.timeText
                                     + (d.location.map { " · \($0)" } ?? ""))
                                    .font(.footnote).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Text("星期").font(.footnote)
                                    Picker("星期", selection: $d.weekday) {
                                        if d.weekday == 0 { Text("請選擇").tag(0) }
                                        ForEach(1...7, id: \.self) {
                                            Text("週" + Course.weekdayNames[$0 - 1]).tag($0)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .tint(d.weekday == 0 ? .red : .accentColor)
                                    if d.weekday == 0 {
                                        Text(d.columnGroup != nil ? "請在上方選這一欄是星期幾" : "星期不明，請選")
                                            .font(.caption).foregroundStyle(.red)
                                    } else if d.weekdayGuessed {
                                        Button {
                                            d.weekdayGuessed = false      // 使用者確認過了
                                        } label: {
                                            Label("沒標題，星期是猜的，點此確認", systemImage: "questionmark.circle")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(.orange)
                                    }
                                }
                                if let note = d.mergeNote, d.weekdayGuessed {
                                    Text(note).font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text(headerText)
                }
            }
            .navigationTitle("匯入課表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入課表（\(selectedCount)）") { save() }
                        .disabled(selectedCount == 0 || termEnd < termStart || hasUnknownWeekday)
                }
            }
        }
    }

    private func save() {
        let courses: [Course] = drafts.filter(\.isSelected).compactMap { d in
            guard let s = d.startMinute, let e = d.endMinute, e > s, (1...7).contains(d.weekday) else { return nil }
            return Course(name: d.name, weekday: d.weekday, startMinute: s, endMinute: e,
                          location: d.location, termStart: termStart, termEnd: termEnd)
        }
        CourseStore.shared.add(courses)
        dismiss()
    }
}
