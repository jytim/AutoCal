import SwiftUI

/// 月曆：單日行程是小標籤，跨多天的行程不畫長條——
/// 只在第一天和最後一天放標籤，中間幾天在格子底部畫一條細色條並標「第N天」，
/// 這樣當天的其他行程不會被擠成「+N個」。
struct MonthView: View {
    @StateObject private var vm = MonthViewModel()
    @State private var selectedDay: Date?

    /// 格子高度與每格最多顯示幾列：iPhone 固定 100pt、3 列；
    /// 寬螢幕（iPad / Mac）依可用高度把格子撐高，多顯示幾列行程。
    @State private var cellHeight: CGFloat = 100
    private var maxRows: Int { cellHeight >= 150 ? 5 : (cellHeight >= 120 ? 4 : 3) }

    private static let title: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "yyyy年M月"
        return f
    }()
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthBar
                if vm.accessDenied {
                    Spacer()
                    Label("需要行事曆權限才能顯示月曆，請到「設定」開啟。", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                } else {
                    weekdayHeader
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(vm.weeks.enumerated()), id: \.offset) { _, week in
                                    HStack(spacing: 0) {
                                        ForEach(week, id: \.self) { day in
                                            cell(for: day)
                                                .onTapGesture { selectedDay = day }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 80)
                        }
                        .onAppear { updateCellHeight(geo.size.height) }
                        .onChange(of: geo.size.height) { _, h in updateCellHeight(h) }
                        .onChange(of: vm.weeks.count) { _, _ in updateCellHeight(geo.size.height) }
                    }
                }
            }
            .navigationTitle("月曆")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await vm.load() } }
            .sheet(item: Binding(get: { selectedDay.map(DayID.init) },
                                 set: { selectedDay = $0?.day })) { id in
                DaySheet(day: id.day, spans: vm.spans(on: id.day), singles: vm.singles(on: id.day))
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 標頭

    private var monthBar: some View {
        HStack {
            Button { vm.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(Self.title.string(from: vm.monthStart)).font(.subheadline.bold())
                Button("回到本月") { vm.goToThisMonth() }.font(.caption)
            }
            Spacer()
            Button { vm.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func updateCellHeight(_ available: CGFloat) {
        let rows = max(vm.weeks.count, 5)
        // 留 90pt 給浮動分頁列；iPhone 上算出來通常小於 100，就維持 100
        cellHeight = max(100, (available - 90) / CGFloat(rows))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { w in
                Text(w)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 一格

    private enum Row: Identifiable {
        case tripStart(MonthEvent)
        case tripEnd(MonthEvent)
        case allDay(MonthEvent)
        case timed(MonthEvent)

        var id: String {
            switch self {
            case .tripStart(let e): return "s" + e.id
            case .tripEnd(let e): return "e" + e.id
            case .allDay(let e): return "a" + e.id
            case .timed(let e): return "t" + e.id
            }
        }
    }

    private func rows(for day: Date) -> [Row] {
        var out: [Row] = []
        for s in vm.spans(on: day) {
            if s.isStart { out.append(.tripStart(s.event)) }
            if s.isEnd { out.append(.tripEnd(s.event)) }
        }
        for e in vm.singles(on: day) {
            out.append(e.isAllDay ? .allDay(e) : .timed(e))
        }
        return out
    }

    private func cell(for day: Date) -> some View {
        let spans = vm.spans(on: day)
        let all = rows(for: day)
        let visible = all.count > maxRows ? Array(all.prefix(maxRows - 1)) : all
        let hidden = all.count - visible.count
        let isToday = Calendar.current.isDateInToday(day)
        // 中間幾天（不是第一天也不是最後一天）才在標題旁標「第N天」
        let middle = spans.first { !$0.isStart && !$0.isEnd }

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())
                Spacer(minLength: 0)
                if let m = middle {
                    Text("第\(m.dayNumber)天")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(m.event.color)
                }
            }
            ForEach(visible) { row in rowView(row) }
            if hidden > 0 {
                Text("+\(hidden)個")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { strips(for: spans) }
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .opacity(vm.isInMonth(day) ? 1 : 0.4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .tripStart(let e):
            tripChip(e, symbol: "flag.fill")
        case .tripEnd(let e):
            tripChip(e, symbol: "flag.checkered")
        case .allDay(let e):
            Text(e.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(e.color.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .timed(let e):
            HStack(spacing: 3) {
                Circle().fill(e.color).frame(width: 5, height: 5)
                Text(e.title).font(.system(size: 10)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tripChip(_ e: MonthEvent, symbol: String) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 6))
            Text(e.title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(e.color)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// 跨多天行程在整段期間的底部細色條（不占版面，其他行程不會被擠掉）。
    private func strips(for spans: [TripSpan]) -> some View {
        VStack(spacing: 1) {
            ForEach(spans) { s in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(s.event.color)
                    .frame(height: 3)
                    .padding(.leading, s.isStart ? 3 : 0)
                    .padding(.trailing, s.isEnd ? 3 : 0)
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - 點一天看詳情

private struct DayID: Identifiable {
    let day: Date
    var id: Date { day }
}

private struct DaySheet: View {
    let day: Date
    let spans: [TripSpan]
    let singles: [MonthEvent]
    @Environment(\.dismiss) private var dismiss

    private static let header: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let md: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if spans.isEmpty && singles.isEmpty {
                    Text("這天沒有行程").foregroundStyle(.secondary)
                }
                ForEach(spans) { s in
                    row(s.event,
                        subtitle: "\(Self.md.string(from: s.event.firstDay)) – \(Self.md.string(from: s.event.lastDay))（第\(s.dayNumber)／\(s.totalDays)天）")
                }
                ForEach(singles) { e in
                    row(e, subtitle: e.isAllDay ? "整天"
                        : "\(Self.hm.string(from: e.start)) – \(Self.hm.string(from: e.end))")
                }
            }
            .navigationTitle(Self.header.string(from: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func row(_ e: MonthEvent, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(e.color).frame(width: 8, height: 8)
                Text(e.title).font(.headline)
            }
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            if let loc = e.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse").font(.footnote)
            }
            if let notes = e.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
