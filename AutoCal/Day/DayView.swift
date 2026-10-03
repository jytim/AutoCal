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
            .navigationTitle("日程")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vm.allDay) { item in
                HStack(spacing: 6) {
                    Text(item.title).font(.footnote.weight(.semibold))
                    if let p = item.progress {
                        Text(p).font(.caption2).opacity(0.9)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(item.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - 時間軸

    /// 顯示的時段：預設 8–22 點，有行程超出就往外擴，讓整天剛好塞進一頁、不用捲動。
    private var hourRange: (start: Int, end: Int) {
        let cal = Calendar.current
        var s = 8, e = 22
        for ev in vm.timed {
            s = min(s, cal.component(.hour, from: ev.start))
            let endH = cal.component(.hour, from: ev.end) + (cal.component(.minute, from: ev.end) > 0 ? 1 : 0)
            e = max(e, ev.end > cal.startOfDay(for: vm.day).addingTimeInterval(86400 - 1) ? 24 : endH)
        }
        return (max(s, 0), min(max(e, s + 1), 24))
    }

    private var timeline: some View {
        GeometryReader { geo in
            let r = hourRange
            let hours = r.end - r.start
            // 底部留給浮動的分頁列，整天才不會被蓋住
            let hh = min((geo.size.height - 84) / CGFloat(hours), 64)
            let contentWidth = geo.size.width - timeColWidth - 12
            ZStack(alignment: .topLeading) {
                ForEach(0..<hours, id: \.self) { i in
                    let y = CGFloat(i) * hh
                    Text(String(format: "%02d", r.start + i))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: timeColWidth - 6, alignment: .trailing)
                        .offset(y: y - 7)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18)).frame(height: 0.5)
                        .padding(.leading, timeColWidth).offset(y: y)
                }

                // 課堂固定放在右側窄欄，行程在左邊；這樣每天都有課也不會和行程混在一起
                let classes = vm.timed.filter { $0.courseID != nil }
                let others = vm.timed.filter { $0.courseID == nil }
                let classW: CGFloat = classes.isEmpty ? 0 : max(contentWidth * 0.27, 78)
                let eventsWidth = contentWidth - (classes.isEmpty ? 0 : classW + 6)
                ForEach(classes) { c in
                    classBlock(c, width: classW, hh: hh, startHour: r.start, totalH: CGFloat(hours) * hh)
                        .offset(x: timeColWidth + 6 + eventsWidth + 6,
                                y: y(of: c.start, hh: hh, startHour: r.start))
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
                    let baseY = y(of: e.start, hh: hh, startHour: r.start)
                    let behindTop = others.compactMap { o -> CGFloat? in
                        guard let oi = lanes[o.id], oi.lane == info.lane - 1, o.start <= e.start, o.end > e.start
                        else { return nil }
                        return y(of: o.start, hh: hh, startHour: r.start)
                    }.max()
                    let shift = max(0, (behindTop.map { $0 + 15 } ?? 0) - baseY)
                    block(e, width: width, stacked: info.count > 1, hh: hh, startHour: r.start,
                          totalH: CGFloat(hours) * hh, shift: shift)
                        .shadow(color: .black.opacity(info.count > 1 ? 0.25 : 0.08), radius: 1.5, y: 1)
                        .offset(x: timeColWidth + 6 + stagger * CGFloat(info.lane),
                                y: baseY + shift)
                        .zIndex(isFront ? 100 : Double(info.lane))
                        .onTapGesture {
                            if info.count > 1 && !onTop {
                                withAnimation(.easeInOut(duration: 0.2)) { front = e.id }
                            } else {
                                selected = e
                            }
                        }
                }

                nowLine(width: geo.size.width - timeColWidth, hh: hh, startHour: r.start, totalH: CGFloat(hours) * hh)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .padding(.top, 7)
        }
        .onChange(of: vm.day) { _, _ in front = nil }
        .onChange(of: vm.timed.count) { _, _ in front = nil }
    }

    private func y(of date: Date, hh: CGFloat, startHour: Int) -> CGFloat {
        let c = Calendar.current
        let minutes = c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
        return max(CGFloat(minutes - startHour * 60) / 60, 0) * hh
    }

    private func block(_ e: TimetableEvent, width: CGFloat, stacked: Bool,
                       hh: CGFloat, startHour: Int, totalH: CGFloat, shift: CGFloat) -> some View {
        // 高度直接用「時間長度」算，這樣結束在午夜（24:00）的行程也不會算錯
        let top = y(of: e.start, hh: hh, startHour: startHour)
        let natural = CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hh
        let height = min(max(natural - shift, 22), max(totalH - top - shift, 22))
        let compact = height < 30
        return VStack(alignment: .leading, spacing: 2) {
            Text(e.title)
                .font(.system(size: compact ? 12 : (stacked ? 12 : 14), weight: .semibold))
                .lineLimit(height > 60 ? 2 : 1)
            if height > 34 {
                Text("\(Self.hm.string(from: e.start))–\(Self.hm.string(from: e.end))")
                    .font(.system(size: 12).monospacedDigit())
                    .opacity(0.92)
            }
            if height > 66, let loc = e.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11)).lineLimit(1).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        // 疊在一起時，後面那張只露出一小條，上下留白要小，標題才不會被前面那張蓋住
        .padding(.top, (stacked || compact) ? 1 : 5)
        .padding(.bottom, compact ? 0 : 5)
        .frame(width: width, height: height - 1, alignment: .topLeading)
        .background(e.color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.7), lineWidth: 0.8))
    }

    /// 右側窄欄裡的課堂：縮短版，只放課名、時間、教室。
    private func classBlock(_ e: TimetableEvent, width: CGFloat, hh: CGFloat,
                            startHour: Int, totalH: CGFloat) -> some View {
        let top = y(of: e.start, hh: hh, startHour: startHour)
        let natural = CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hh
        let height = min(max(natural, 22), max(totalH - top, 22))
        return VStack(alignment: .leading, spacing: 1) {
            Text(e.title).font(.system(size: 11, weight: .semibold)).lineLimit(height > 52 ? 2 : 1)
            if height > 34 {
                Text(Self.hm.string(from: e.start)).font(.system(size: 10).monospacedDigit()).opacity(0.9)
            }
            if height > 52, let loc = e.location, !loc.isEmpty {
                Text(loc).font(.system(size: 10)).lineLimit(1).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.top, 2)
        .frame(width: width, height: height - 1, alignment: .topLeading)
        .background(e.color.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
