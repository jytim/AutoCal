import SwiftUI

/// 日程：單日檢視。上面放整天的項目，下面是這一天的時間軸（行程與課堂）。
/// 月曆點某一天會跳到這裡。
struct DayView: View {
    @ObservedObject var vm: DayViewModel
    @ObservedObject private var courseStore = CourseStore.shared
    @State private var selected: TimetableEvent?
    @State private var courseToEdit: Course?
    /// 被點到最前面的疊放卡片（nil = 照預設順序）。
    @State private var front: String?
    /// 日程預設顯示的時段（設定裡可改）；當天有行程超出時仍會自動往外擴。
    @AppStorage("ui.dayStartHour") private var baseStart = 8
    @AppStorage("ui.dayEndHour") private var baseEnd = 22
    /// "timeline" = 時間軸格子（預設，單日維度）、"agenda" = 議程清單
    @AppStorage("ui.dayMode") private var mode = "timeline"

    private let timeColWidth: CGFloat = 40

    private static let title: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M月d日 EEEE"; return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayBar
                if vm.accessDenied {
                    Label("沒有行事曆權限，目前只顯示課堂。可到「設定」開啟。", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal).padding(.bottom, 4)
                }
                if !vm.allDay.isEmpty { allDayStrip }
                if mode == "agenda" { agenda } else { timeline }
            }
            // 分頁列已經寫了「日程」，上面不再重複標題，把空間留給時間軸
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { Task { await vm.load() } }
            .onReceive(courseStore.$courses) { _ in Task { await vm.load() } }
            .sheet(item: $selected) { event in
                EventDetailSheet(
                    event: event,
                    onEdit: {
                        guard let id = event.courseID,
                              let c = courseStore.courses.first(where: { $0.id == id }) else { return }
                        selected = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { courseToEdit = c }
                    },
                    onSkip: {
                        guard let id = event.courseID else { return }
                        CourseStore.shared.skip(courseID: id, on: event.start)
                        selected = nil
                    },
                    onDelete: {
                        guard let id = event.courseID else { return }
                        CourseStore.shared.delete(id: id)
                        selected = nil
                    })
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $courseToEdit) { c in CourseFormView(editing: c) }
        }
    }

    // MARK: - 日期列

    private var dayBar: some View {
        HStack {
            Button { vm.shift(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(Self.title.string(from: vm.day)).font(.subheadline.bold())
                if !Calendar.current.isDateInToday(vm.day) {
                    Button("回到今天") { vm.select(Date()) }.font(.caption)
                }
            }
            Spacer()
            Button {
                mode = (mode == "agenda") ? "timeline" : "agenda"
            } label: {
                Image(systemName: mode == "agenda" ? "calendar.day.timeline.left" : "list.bullet")
            }
            .padding(.trailing, 14)
            Button { vm.shift(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 整天項目

    private var allDayStrip: some View {
        // 整天項目縮成一排小標籤（可橫向滑動），不再每個佔一整條
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.allDay) { item in
                    HStack(spacing: 5) {
                        Circle().fill(item.color).frame(width: 7, height: 7)
                        Text(item.title).font(.caption.weight(.semibold))
                        if let p = item.progress {
                            Text(p.replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "天", with: ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(item.color.opacity(0.17))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 6)
    }

    // MARK: - 議程清單

    private enum AgendaRow: Identifiable {
        case item(TimetableEvent, overlaps: Bool)
        case gap(Date, Date)
        var id: String {
            switch self {
            case .item(let e, _): return e.id
            case .gap(let s, _): return "gap-\(s.timeIntervalSince1970)"
            }
        }
    }

    /// 依時間排好的清單，項目之間空檔 30 分鐘以上就插一列「空檔」；和前面項目時間重疊的標警告。
    private func agendaRows() -> [AgendaRow] {
        var rows: [AgendaRow] = []
        var cursor: Date?
        for e in vm.timed.sorted(by: { $0.start < $1.start }) {
            if let c = cursor {
                if e.start >= c.addingTimeInterval(30 * 60) { rows.append(.gap(c, e.start)) }
                rows.append(.item(e, overlaps: e.start < c))
                cursor = max(c, e.end)
            } else {
                rows.append(.item(e, overlaps: false))
                cursor = e.end
            }
        }
        return rows
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let m = max(Int(seconds / 60), 0)
        if m < 60 { return "\(m) 分鐘" }
        return m % 60 == 0 ? "\(m / 60) 小時" : "\(m / 60) 小時 \(m % 60) 分"
    }

    private var agenda: some View {
        TimelineView(.everyMinute) { ctx in
            let now = ctx.date
            let isToday = Calendar.current.isDateInToday(vm.day)
            let rows = agendaRows()
            let nextID = isToday
                ? vm.timed.filter { $0.start > now }.min(by: { $0.start < $1.start })?.id : nil
            ScrollView {
                LazyVStack(spacing: 8) {
                    if rows.isEmpty {
                        Text("這天沒有行程")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                    ForEach(rows) { row in
                        switch row {
                        case .gap(let s, let e):
                            Text("空檔 \(Self.durationText(e.timeIntervalSince(s)))　\(Self.hm.string(from: s))–\(Self.hm.string(from: e))")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        case .item(let e, let overlaps):
                            agendaItem(e, overlaps: overlaps, now: isToday ? now : nil, isNext: e.id == nextID)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 100)
            }
        }
    }

    private func agendaItem(_ e: TimetableEvent, overlaps: Bool, now: Date?, isNext: Bool) -> some View {
        let ongoing = now.map { e.start <= $0 && $0 < e.end } ?? false
        let past = now.map { e.end <= $0 } ?? false
        var status: String?
        if ongoing, let n = now { status = "進行中・還剩 \(Self.durationText(e.end.timeIntervalSince(n)))" }
        else if isNext, let n = now { status = "下一件・還有 \(Self.durationText(e.start.timeIntervalSince(n)))" }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.hm.string(from: e.start))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text(Self.hm.string(from: e.end))
                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    if e.courseID != nil {
                        Text("課").font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(e.color.opacity(0.25)).clipShape(Capsule())
                    }
                }
                if let loc = e.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let status {
                    Text(status).font(.system(size: 12, weight: .semibold)).foregroundStyle(e.color)
                }
                if overlaps {
                    Label("和前面的項目時間重疊", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, 12)
        .frame(maxWidth: .infinity)
        .tintedCard(e.color, radius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(e.color, lineWidth: (ongoing || isNext) ? 1.5 : 0))
        .opacity(past ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { selected = e }
    }

    // MARK: - 時間軸

    /// 設定的基本顯示時段（預設 8–22）。
    private var baseRange: (start: Int, end: Int) {
        let s = min(max(baseStart, 0), 23)
        return (s, min(max(baseEnd, s + 1), 24))
    }

    /// 實際顯示範圍：基本時段，加上當天超出的行程（每天的刻度可能不同，但整天永遠一頁看完）。
    private var fullRange: (start: Int, end: Int) {
        let cal = Calendar.current
        let base = baseRange
        var s = base.start, e = base.end
        let dayEnd = cal.startOfDay(for: vm.day).addingTimeInterval(86400 - 1)
        for ev in vm.timed {
            s = min(s, cal.component(.hour, from: ev.start))
            let endH = ev.end > dayEnd ? 24 : cal.component(.hour, from: ev.end) + (cal.component(.minute, from: ev.end) > 0 ? 1 : 0)
            e = max(e, endH)
        }
        return (max(s, 0), min(max(e, s + 1), 24))
    }

    private struct TimeTag: Identifiable {
        let id = UUID(); let y: CGFloat; let text: String; let color: Color
    }

    /// 每個行程的開始、結束時間標在左邊的時間欄（對齊卡片的上緣與下緣）。
    /// 兩個標籤太近就只留前面那個；時間欄上被它們蓋到的整點標籤會隱藏。
    private func timeTags(hh: CGFloat, startHour: Int) -> [TimeTag] {
        var raw: [TimeTag] = []
        for e in vm.timed {
            raw.append(TimeTag(y: y(of: e.start, hh: hh, startHour: startHour), text: Self.hm.string(from: e.start), color: e.color))
            let endY = y(of: e.start, hh: hh, startHour: startHour) + CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hh
            raw.append(TimeTag(y: endY, text: Self.hm.string(from: e.end), color: e.color))
        }
        var kept: [TimeTag] = []
        for t in raw.sorted(by: { $0.y < $1.y }) {
            if let last = kept.last, t.y - last.y < 11 { continue }
            kept.append(t)
        }
        return kept
    }

    private var timeline: some View {
        GeometryReader { geo in
            let base = baseRange
            let full = fullRange
            let fullHours = full.end - full.start
            // 整天一頁看完：把「基本時段加上超出的行程」剛好塞進畫面；底部留給浮動的分頁列
            let hh = min((geo.size.height - 84) / CGFloat(fullHours), 64)
            let totalH = CGFloat(fullHours) * hh
            let contentWidth = geo.size.width - timeColWidth - 12
            let tags = timeTags(hh: hh, startHour: full.start)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // 整點只留淡淡的橫線，不標數字；左邊只標行程的開始與結束時間
                        ForEach(0...fullHours, id: \.self) { i in
                            let yy = CGFloat(i) * hh
                            Rectangle()
                                .fill(Color.secondary.opacity(0.18)).frame(height: 0.5)
                                .padding(.leading, timeColWidth).offset(y: yy)
                        }
                        ForEach(tags) { t in
                            Text(t.text)
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(t.color)
                                .frame(width: timeColWidth - 4, alignment: .trailing)
                                .offset(y: t.y - 6)
                        }

                        // 課堂固定放在右側窄欄，行程在左邊
                        let classes = vm.timed.filter { $0.courseID != nil }
                        let others = vm.timed.filter { $0.courseID == nil }
                        let classW: CGFloat = classes.isEmpty ? 0 : max(contentWidth * 0.27, 78)
                        let eventsWidth = contentWidth - (classes.isEmpty ? 0 : classW + 6)
                        if !classes.isEmpty {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.06))
                                .frame(width: classW, height: totalH)
                                .offset(x: timeColWidth + 6 + eventsWidth + 6)
                            Text("課")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: classW)
                                .offset(x: timeColWidth + 6 + eventsWidth + 6, y: -13)
                        }
                        ForEach(classes) { c in
                            classBlock(c, width: classW, hh: hh, startHour: full.start, totalH: totalH)
                                .offset(x: timeColWidth + 6 + eventsWidth + 6,
                                        y: y(of: c.start, hh: hh, startHour: full.start))
                                .onTapGesture { selected = c }
                        }

                        let lanes = TimetableViewModel.lanes(for: others)
                        ForEach(others) { e in
                            let info = lanes[e.id] ?? (0, 1)
                            let stagger: CGFloat = info.count > 1 ? 10 : 0
                            let width = eventsWidth - stagger * CGFloat(info.count - 1)
                            let isFront = front == e.id
                            // 預設最後一層在最上面；點一下底下的卡片可以拉到最前面
                            let onTop = info.count > 1 && (isFront || (front == nil && info.lane == info.count - 1))
                            // 疊在後面的卡片至少要露出一條標題的高度；前面那張往下推一點（下緣不動）
                            let baseY = y(of: e.start, hh: hh, startHour: full.start)
                            let behindTop = others.compactMap { o -> CGFloat? in
                                guard let oi = lanes[o.id], oi.lane == info.lane - 1, o.start <= e.start, o.end > e.start
                                else { return nil }
                                return y(of: o.start, hh: hh, startHour: full.start)
                            }.max()
                            let shift = max(0, (behindTop.map { $0 + 15 } ?? 0) - baseY)
                            block(e, width: width, back: info.count > 1 && !onTop, hh: hh,
                                  startHour: full.start, totalH: totalH, shift: shift)
                                .shadow(color: .black.opacity(info.count > 1 ? 0.2 : 0.06), radius: 1.5, y: 1)
                                .offset(x: timeColWidth + 6 + stagger * CGFloat(info.lane), y: baseY + shift)
                                .zIndex(isFront ? 100 : Double(info.lane))
                                .onTapGesture {
                                    if info.count > 1 && !onTop {
                                        withAnimation(.easeInOut(duration: 0.2)) { front = e.id }
                                    } else {
                                        selected = e
                                    }
                                }
                        }

                        nowLine(width: geo.size.width - timeColWidth, hh: hh, startHour: full.start, totalH: totalH)
                    }
                    .frame(width: geo.size.width, height: totalH + 14, alignment: .topLeading)
                    .padding(.top, 16)
                }
                .scrollDisabled(true)
                .onChange(of: vm.day) { _, _ in front = nil }
                .onChange(of: vm.timed.count) { _, _ in front = nil }
            }
        }
    }

    private func y(of date: Date, hh: CGFloat, startHour: Int) -> CGFloat {
        let c = Calendar.current
        let minutes = c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
        return max(CGFloat(minutes - startHour * 60) / 60, 0) * hh
    }

    /// 行程卡片：標題置中；開始、結束時間標在左邊的時間欄。疊在後面的卡片只露出一條，標題貼上緣。
    private func block(_ e: TimetableEvent, width: CGFloat, back: Bool,
                       hh: CGFloat, startHour: Int, totalH: CGFloat, shift: CGFloat) -> some View {
        let top = y(of: e.start, hh: hh, startHour: startHour)
        let natural = CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hh
        let height = min(max(natural - shift, 22), max(totalH - top - shift, 22))
        return VStack(spacing: 2) {
            Text(e.title)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(height > 60 ? 2 : 1)
            if !back, height > 70, let loc = e.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(width: width, height: height - 1, alignment: back ? .top : .center)
        .padding(.top, 0)
        .tintedCard(e.color, radius: 8)
    }

    /// 右側窄欄裡的課堂：和行程同樣式，只是窄一點。
    private func classBlock(_ e: TimetableEvent, width: CGFloat, hh: CGFloat,
                            startHour: Int, totalH: CGFloat) -> some View {
        let top = y(of: e.start, hh: hh, startHour: startHour)
        let natural = CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hh
        let height = min(max(natural, 22), max(totalH - top, 22))
        return VStack(spacing: 1) {
            Text(e.title).font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center).lineLimit(height > 52 ? 2 : 1)
            if height > 70, let loc = e.location, !loc.isEmpty {
                Text(loc).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .padding(.leading, 9).padding(.trailing, 4)
        .frame(width: width, height: height - 1, alignment: .center)
        .tintedCard(e.color, radius: 6, bar: 3)
    }

    @ViewBuilder
    private func nowLine(width: CGFloat, hh: CGFloat, startHour: Int, totalH: CGFloat) -> some View {
        if Calendar.current.isDateInToday(vm.day) {
            let yy = y(of: Date(), hh: hh, startHour: startHour)
            if yy > 0 && yy < totalH {
                Rectangle().fill(Color.red).frame(width: width, height: 1)
                    .offset(x: timeColWidth, y: yy)
                Circle().fill(Color.red).frame(width: 7, height: 7)
                    .offset(x: timeColWidth - 3, y: yy - 3)
            }
        }
    }
}
