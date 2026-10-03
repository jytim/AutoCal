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
                            set: { item.start = $0; item.timeWarning = nil }),
                           displayedComponents: item.allDay ? [.date] : [.date, .hourAndMinute])
                Toggle("整天", isOn: $item.allDay)
                    .font(.subheadline)
            } else {
                DatePicker("截止",
                           selection: Binding(
                            get: { item.start ?? item.end ?? Date() },
                            set: { item.start = $0; item.timeWarning = nil }),
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
            if let w = item.timeWarning {
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !item.conflicts.isEmpty {
                conflictSection
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(item.isSelected && item.resolution != .skip ? 1 : 0.5)
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// AI 建議的處理方式只用來顯示提示文字，不會預先選取——一律要使用者自己點選。
    private var recommendationLabel: String {
        switch item.aiRecommendation {
        case .overlap: return "AI 建議：一起排"
        case .move: return "AI 建議：改到建議時間"
        case .skip: return "AI 建議：不加入"
        default: return ""
        }
    }

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("時間衝突", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            ForEach(item.conflicts) { c in
                Text("・\(c.title)  \(Self.hm.string(from: c.start))–\(Self.hm.string(from: c.end))")
                    .font(.caption)
            }
            if let note = item.aiNote, !note.isEmpty {
                Text("AI 判斷：\(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !recommendationLabel.isEmpty {
                Text(recommendationLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }

            Text("請選擇處理方式（AI 不會替你決定）")
                .font(.caption2)
                .foregroundStyle(item.resolution == .undecided ? .red : .secondary)

            // 刻意不綁定預設值：使用者沒點過之前，這裡不會有任何選項被選取。
            Picker("處理方式", selection: $item.resolution) {
                Text("請選擇").tag(ParsedItem.Resolution.undecided).hidden()
                Text("一起排").tag(ParsedItem.Resolution.overlap)
                if let s = item.suggestedStart {
                    Text("改到 \(Self.hm.string(from: s))").tag(ParsedItem.Resolution.move)
                }
                Text("不加入").tag(ParsedItem.Resolution.skip)
            }
            .pickerStyle(.segmented)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
