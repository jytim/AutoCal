import SwiftUI

/// 單一解析項目的可編輯確認卡片。
struct ItemCard: View {
    @Binding var item: ParsedItem

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d (E) HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.type == .event ? "calendar" : "checklist")
                    .foregroundStyle(item.type == .event ? .blue : .orange)
                Picker("", selection: $item.type) {
                    Text("行程").tag(ParsedItem.Kind.event)
                    Text("待辦").tag(ParsedItem.Kind.todo)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Spacer()
                Toggle("", isOn: $item.isSelected)
                    .labelsHidden()
            }

            TextField("標題", text: $item.title)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            if item.type == .event {
                DatePicker("開始",
                           selection: Binding(
                            get: { item.start ?? Date() },
                            set: { item.start = $0 }),
                           displayedComponents: item.allDay ? [.date] : [.date, .hourAndMinute])
                Toggle("整天", isOn: $item.allDay)
                    .font(.subheadline)
            } else {
                DatePicker("截止",
                           selection: Binding(
                            get: { item.start ?? item.end ?? Date() },
                            set: { item.start = $0 }),
                           displayedComponents: [.date, .hourAndMinute])
            }

            HStack {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                TextField("地點（可留空）",
                          text: Binding(get: { item.location ?? "" },
                                        set: { item.location = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
            }

            if item.start == nil {
                Label("時間不確定，請確認", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(item.isSelected ? 1 : 0.5)
    }
}
