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
                timeline
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

    // MARK: - 時間軸

    /// 設定的基本顯示時段。比例（每小時多高）永遠用它算，所以每天看起來尺度一致。
    private var baseRange: (start: Int, end: Int) {
        let s = min(max(baseStart, 0), 23)
        return (s, min(max(baseEnd, s + 1), 24))
    }

    /// 實際內容範圍：基本時段，加上當天超出的行程。超出的部分用捲動看，不壓縮比例。
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
            let baseHours = base.end - base.start
            let fullHours = full.end - full.start
            // 底部留給浮動的分頁列；每小時高度只由基本時段決定
            let hh = min((geo.size.height - 84) / CGFloat(baseHours), 64)
            let totalH = CGFloat(fullHours) * hh
            let contentWidth = geo.size.width - timeColWidth - 12
            let tags = timeTags(hh: hh, startHour: full.start)
            let earlyCount = vm.timed.filter { Calendar.current.component(.hour, from: $0.start) < base.start }.count
            let lateCount = vm.timed.filter { ev in
                let cal = Calendar.current
                let dayEnd = cal.startOfDay(for: vm.day).addingTimeInterval(86400 - 1)
                let endH = ev.end > dayEnd ? 24 : cal.component(.hour, from: ev.end) + (cal.component(.minute, from: ev.end) > 0 ? 1 : 0)
                return endH > base.end
            }.count

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // 捲動用的隱形錨點
                        Color.clear.frame(width: 1, height: 1).id("top")
                        Color.clear.frame(width: 1, height: 1).id("base").offset(y: CGFloat(base.start - full.start) * hh - 8)
                        Color.clear.frame(width: 1, height: 1).id("bottom").offset(y: totalH)

                        // 最下方的結束時間也標出來
                        ForEach(0...fullHours, id: \.self) { i in
                            let yy = CGFloat(i) * hh
                            if !tags.contains(where: { abs($0.y - yy) < 9 }) {
                                Text(String(format: "%02d", full.start + i))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .frame(width: timeColWidth - 6, alignment: .trailing)
                                    .offset(y: yy - 7)
                            }
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
                    .padding(.top, 7)
                }
                .scrollDisabled(fullHours == baseHours)
                // 超出基本時段的行程：比例不變，捲動才看得到，並在邊緣提示
                .overlay(alignment: .top) {
                    if earlyCount > 0 {
                        edgePill("較早還有 \(earlyCount) 項", systemImage: "chevron.up") {
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if lateCount > 0 {
                        edgePill("較晚還有 \(lateCount) 項", systemImage: "chevron.down") {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .onAppear { DispatchQueue.main.async { proxy.scrollTo("base", anchor: .top) } }
                .onChange(of: vm.day) { _, _ in
                    front = nil
                    DispatchQueue.main.async { proxy.scrollTo("base", anchor: .top) }
                }
                .onChange(of: vm.timed.count) { _, _ in
                    front = nil
                    DispatchQueue.main.async { proxy.scrollTo("base", anchor: .top) }
                }
            }
        }
    }

    private func edgePill(_ text: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
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
