import SwiftUI

/// 單一解析項目的可編輯確認卡片。
struct ItemCard: View {
    @Binding var item: ParsedItem
    @State private var calendars: [CalendarChoice] = []

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
                // 關掉就不會加入這一筆（一次解析出好幾筆時，用來挑要哪幾筆）
                Toggle("加入", isOn: $item.isSelected)
                    .fixedSize()
            }
            Text(item.type == .event
                 ? "行程：會寫進「行事曆」（沒寫時間就是整天，關掉「整天」可設時間）"
                 : "待辦：只看截止時間，會寫進「提醒事項」")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("標題", text: $item.title)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            if item.type == .event {
                DatePicker("開始",
                           selection: Binding(
                            get: { item.start ?? Date() },
                            set: { new in
                                let old = item.start
                                item.start = new
                                // 已經有明確結束時間時，維持原本的長度一起平移
                                if let e = item.end, let o = old {
                                    item.end = new.addingTimeInterval(e.timeIntervalSince(o))
                                }
                                item.timeWarning = nil
                            }),
                           displayedComponents: item.allDay ? [.date] : [.date, .hourAndMinute])
                if !item.allDay {
                    DatePicker("結束",
                               selection: Binding(
                                get: { item.end ?? (item.start ?? Date()).addingTimeInterval(3600) },
                                set: { item.end = $0 }),
                               in: (item.start ?? Date())...,
                               displayedComponents: [.date, .hourAndMinute])
                    if item.end == nil {
                        Text("沒寫結束時間，先抓 1 小時，可以自己改")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("整天", isOn: Binding(
                    get: { item.allDay },
                    set: { on in
                        item.allDay = on
                        // 從整天改成有時間：起點若還在午夜，先放 09:00，不要變成午夜行程
                        if !on, let s = item.start {
                            let cal = Calendar.current
                            if cal.component(.hour, from: s) == 0 && cal.component(.minute, from: s) == 0 {
                                item.start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: s)
                                item.end = nil
                            }
                        }
                    }))
                    .font(.subheadline)
                if calendars.count > 1 {
                    HStack {
                        Text("行事曆").font(.subheadline)
                        Spacer()
                        Picker("行事曆", selection: Binding(
                            get: { item.calendarID ?? calendars.first(where: \.isDefault)?.id ?? "" },
                            set: { item.calendarID = $0 })) {
                            ForEach(calendars) { c in
                                Label(c.title, systemImage: "circle.fill")
                                    .tint(c.color)
                                    .tag(c.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
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
        .task { calendars = CalendarChoice.load() }
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


/// 一次解析出好幾個項目時，把它們全部設成同一個時段（各自保留自己的日期）。
/// 例如一張截圖裡的六堂課都在 19:00–21:00。只套用在已勾選、有日期的項目。
struct BatchTimeBar: View {
    @Binding var items: [ParsedItem]
    /// 套用後通知外面重新檢查衝突。
    var onApplied: () -> Void = {}

    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()

    private var targets: [Int] {
        items.indices.filter { items[$0].isSelected && items[$0].start != nil }
    }

    private var isValid: Bool {
        let cal = Calendar.current
        func m(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        return m(end) > m(start)
    }

    var body: some View {
        if targets.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Label("全部設為同一時段", systemImage: "clock.arrow.2.circlepath")
                    .font(.subheadline.bold())
                DatePicker("開始", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("結束", selection: $end, displayedComponents: .hourAndMinute)
                if !isValid {
                    Text("結束時間要晚於開始時間").font(.caption).foregroundStyle(.red)
                }
                Button {
                    apply()
                } label: {
                    Text("套用到已勾選的 \(targets.count) 項")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isValid)
                Text("各項目保留自己的日期，只統一開始和結束時間；不想套用的先取消勾選。套用後可以再逐張修改。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func apply() {
        let cal = Calendar.current
        let sc = cal.dateComponents([.hour, .minute], from: start)
        let ec = cal.dateComponents([.hour, .minute], from: end)
        for i in targets {
            guard let day = items[i].start else { continue }
            items[i].type = .event
            items[i].allDay = false
            items[i].start = cal.date(bySettingHour: sc.hour ?? 9, minute: sc.minute ?? 0, second: 0, of: day)
            items[i].end = cal.date(bySettingHour: ec.hour ?? 10, minute: ec.minute ?? 0, second: 0, of: day)
            items[i].timeWarning = nil
        }
        onApplied()
    }
}
