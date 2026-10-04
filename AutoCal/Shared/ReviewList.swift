import SwiftUI

/// 確認清單：每個項目先收成一行摘要，點一下才展開成完整編輯卡片。
/// 主 App 與分享選單共用。
struct ReviewSection: View {
    @Binding var items: [ParsedItem]
    var isBusy = false
    var onRecheck: () -> Void

    @State private var expanded: Set<UUID> = []

    private var undecidedIDs: [UUID] {
        items.filter { $0.isSelected && $0.resolution == .undecided }.map(\.id)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d (E)"; return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("確認要加入的項目").font(.headline)
                Spacer()
                Button(allSelected ? "全不選" : "全選") {
                    let on = !allSelected
                    for i in items.indices { items[i].isSelected = on }
                }
                .font(.footnote)
                Button(action: onRecheck) {
                    Label("重新檢查衝突", systemImage: "arrow.triangle.2.circlepath").font(.footnote)
                }
                .disabled(isBusy)
            }

            BatchTimeBar(items: $items, onApplied: onRecheck)

            ForEach($items) { $item in
                VStack(spacing: 0) {
                    row($item)
                    if expanded.contains(item.id) {
                        ItemCard(item: $item).padding(.top, 6)
                    }
                }
            }
        }
        .onAppear { expanded.formUnion(undecidedIDs) }
        // 有衝突、還沒選處理方式的項目一出現就自動展開，不然使用者會卡在「為什麼不能加入」
        .onChange(of: undecidedIDs) { _, ids in expanded.formUnion(ids) }
    }

    private var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.isSelected) }

    private func row(_ item: Binding<ParsedItem>) -> some View {
        let it = item.wrappedValue
        let open = expanded.contains(it.id)
        return HStack(spacing: 10) {
            Button {
                item.isSelected.wrappedValue.toggle()
            } label: {
                Image(systemName: it.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(it.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(it.title.isEmpty ? "（沒有標題）" : it.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Image(systemName: it.type == .event ? "calendar" : "checklist")
                        .font(.caption2)
                    Text(summary(it)).font(.caption)
                }
                .foregroundStyle(.secondary)
                if let flag = flag(it) {
                    Label(flag.text, systemImage: flag.icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(flag.color)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(it.isSelected && it.resolution != .skip ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if open { expanded.remove(it.id) } else { expanded.insert(it.id) }
            }
        }
    }

    private func summary(_ it: ParsedItem) -> String {
        guard let s = it.start else {
            return it.type == .todo ? "待辦・沒有日期" : "時間不確定"
        }
        let d = Self.day.string(from: s)
        if it.type == .todo {
            return ItemCard.hasClockTime(s) ? "待辦・截止 \(d) \(Self.hm.string(from: s))" : "待辦・截止 \(d)"
        }
        if it.allDay { return "\(d)・整天" }
        let end = it.end.flatMap { $0 > s ? $0 : nil } ?? s.addingTimeInterval(3600)
        return "\(d)・\(Self.hm.string(from: s))–\(Self.hm.string(from: end))"
    }

    private func flag(_ it: ParsedItem) -> (text: String, icon: String, color: Color)? {
        if !it.conflicts.isEmpty && it.isSelected {
            switch it.resolution {
            case .undecided:
                return ("撞到 \(it.conflicts.count) 個行程，請選擇處理方式", "exclamationmark.triangle.fill", .red)
            case .overlap: return ("撞時間・一起排", "exclamationmark.triangle", .orange)
            case .move: return ("撞時間・改到建議時間", "exclamationmark.triangle", .orange)
            case .skip: return ("撞時間・不加入", "exclamationmark.triangle", .orange)
            case .none: return nil
            }
        }
        if let w = it.timeWarning { return (w, "exclamationmark.triangle.fill", .orange) }
        if it.start == nil { return ("時間不確定，請確認", "questionmark.circle", .orange) }
        return nil
    }
}

/// 固定在畫面最下方的加入按鈕：不用滑到清單底部才找得到。
struct ReviewAddBar: View {
    let items: [ParsedItem]
    var onSave: () -> Void

    private var undecided: Int { items.filter { $0.isSelected && $0.resolution == .undecided }.count }
    private var count: Int { items.filter { $0.isSelected && $0.resolution != .skip }.count }

    var body: some View {
        VStack(spacing: 6) {
            if undecided > 0 {
                Label("還有 \(undecided) 項衝突要先選擇處理方式", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button(action: onSave) {
                Label(count == 0 ? "沒有選取任何項目" : "加入 \(count) 項",
                      systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(undecided > 0 || count == 0)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}
