import SwiftUI

/// 新增或編輯一門課（每週重複）。
struct CourseFormView: View {
    @Environment(\.dismiss) private var dismiss
    let editing: Course?

    @State private var name: String
    @State private var weekday: Int
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var termStart: Date
    @State private var termEnd: Date
    @State private var color: Color
    @State private var customColor: Bool

    init(editing: Course?) {
        self.editing = editing
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func time(_ minutes: Int) -> Date {
            cal.date(byAdding: .minute, value: minutes, to: today) ?? today
        }
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? today
        _name = State(initialValue: editing?.name ?? "")
        _weekday = State(initialValue: editing?.weekday ?? 1)
        _start = State(initialValue: time(editing?.startMinute ?? 9 * 60 + 10))
        _end = State(initialValue: time(editing?.endMinute ?? 10 * 60))
        _location = State(initialValue: editing?.location ?? "")
        _color = State(initialValue: editing.map { EventColor.color(for: $0) } ?? Color(red: 0.23, green: 0.51, blue: 0.96))
        _customColor = State(initialValue: editing?.colorHex != nil)
        _termStart = State(initialValue: editing?.termStart ?? weekStart)
        _termEnd = State(initialValue: editing?.termEnd
                         ?? cal.date(byAdding: .day, value: 18 * 7 - 1, to: weekStart) ?? weekStart)
    }

    private var minutes: (start: Int, end: Int) {
        let cal = Calendar.current
        func m(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        return (m(start), m(end))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && minutes.end > minutes.start && termEnd >= termStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("課程") {
                    TextField("課程名稱", text: $name)
                    TextField("教室（可留空）", text: $location)
                    ColorPicker("顏色", selection: Binding(get: { color },
                                                         set: { color = $0; customColor = true }),
                                supportsOpacity: false)
                    if customColor {
                        Button("改回自動配色") { customColor = false }.font(.footnote)
                    }
                }
                Section("每週上課時間") {
                    Picker("星期", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text("週" + Course.weekdayNames[$0 - 1]).tag($0) }
                    }
                    DatePicker("開始", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("結束", selection: $end, displayedComponents: .hourAndMinute)
                    if minutes.end <= minutes.start {
                        Text("結束時間要晚於開始時間").font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("學期範圍") {
                    DatePicker("第一天", selection: $termStart, displayedComponents: .date)
                    DatePicker("最後一天", selection: $termEnd, displayedComponents: .date)
                }
            }
            .navigationTitle(editing == nil ? "新增課堂" : "編輯課堂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let loc = location.trimmingCharacters(in: .whitespaces)
        var course = editing ?? Course(name: "", weekday: weekday, startMinute: 0, endMinute: 0,
                                       termStart: termStart, termEnd: termEnd)
        course.name = name.trimmingCharacters(in: .whitespaces)
        course.weekday = weekday
        course.startMinute = minutes.start
        course.endMinute = minutes.end
        course.location = loc.isEmpty ? nil : loc
        course.termStart = termStart
        course.termEnd = termEnd
        course.colorHex = customColor ? color.hexString : nil
        if editing == nil { CourseStore.shared.add([course]) } else { CourseStore.shared.update(course) }
        dismiss()
    }
}
