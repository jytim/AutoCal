import SwiftUI

/// 日程：單日檢視。上面放整天的項目，下面是這一天的時間軸（行程與課堂）。
/// 月曆點某一天會跳到這裡。
struct DayView: View {
    @ObservedObject var vm: DayViewModel
    @ObservedObject private var courseStore = CourseStore.shared
    @State private var selected: TimetableEvent?
    @State private var courseToEdit: Course?

    private let hourHeight: CGFloat = 56
    private let timeColWidth: CGFloat = 40

    private var totalHours: Int { DayViewModel.endHour - DayViewModel.startHour }

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

    private var timeline: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - timeColWidth - 12
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<totalHours, id: \.self) { i in
                            let y = CGFloat(i) * hourHeight
                            Text(String(format: "%02d", DayViewModel.startHour + i))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(width: timeColWidth - 6, alignment: .trailing)
                                .offset(y: y - 7)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.18)).frame(height: 0.5)
                                .padding(.leading, timeColWidth).offset(y: y)
                            // 捲動定位用的隱形錨點
                            Color.clear.frame(width: 1, height: 1).id(DayViewModel.startHour + i).offset(y: y)
                        }

                        let lanes = TimetableViewModel.lanes(for: vm.timed)
                        ForEach(vm.timed) { e in
                            let info = lanes[e.id] ?? (0, 1)
                            let stagger: CGFloat = info.count > 1 ? 10 : 0
                            let width = contentWidth - stagger * CGFloat(info.count - 1)
                            block(e, width: width, stacked: info.count > 1)
                                .shadow(color: .black.opacity(info.count > 1 ? 0.25 : 0.08), radius: 1.5, y: 1)
                                .offset(x: timeColWidth + 6 + stagger * CGFloat(info.lane), y: y(of: e.start))
                                .zIndex(Double(info.lane))
                                .onTapGesture { selected = e }
                        }

                        nowLine(width: geo.size.width - timeColWidth)
                    }
                    .frame(height: CGFloat(totalHours) * hourHeight, alignment: .topLeading)
                    .padding(.bottom, 90)
                }
                .onAppear { scrollToRelevantHour(proxy) }
                .onChange(of: vm.day) { _, _ in scrollToRelevantHour(proxy) }
                .onChange(of: vm.timed.count) { _, _ in scrollToRelevantHour(proxy) }
            }
        }
    }

    /// 今天捲到現在前一小時；其他天捲到第一件事前一小時（沒事就 8 點）。
    private func scrollToRelevantHour(_ proxy: ScrollViewProxy) {
        let cal = Calendar.current
        var hour = 8
        if cal.isDateInToday(vm.day) {
            hour = cal.component(.hour, from: Date()) - 1
        } else if let first = vm.timed.first {
            hour = cal.component(.hour, from: first.start) - 1
        }
        hour = min(max(hour, DayViewModel.startHour), DayViewModel.endHour - 1)
        DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }
    }

    private func y(of date: Date) -> CGFloat {
        let c = Calendar.current
        let minutes = c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
        return max(CGFloat(minutes - DayViewModel.startHour * 60) / 60, 0) * hourHeight
    }

    private func block(_ e: TimetableEvent, width: CGFloat, stacked: Bool) -> some View {
        // 高度直接用「時間長度」算，這樣結束在午夜（24:00）的行程也不會算錯
        let top = y(of: e.start)
        let natural = CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hourHeight
        let height = min(max(natural, 26), CGFloat(totalHours) * hourHeight - top)
        return VStack(alignment: .leading, spacing: 2) {
            Text(e.title)
                .font(.system(size: stacked ? 13 : 14, weight: .semibold))
                .lineLimit(height > 60 ? 2 : 1)
            if height > 36 {
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
        .padding(.top, stacked ? 2 : 5)
        .padding(.bottom, 5)
        .frame(width: width, height: height - 1, alignment: .topLeading)
        .background(e.color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.7), lineWidth: 0.8))
    }

    @ViewBuilder
    private func nowLine(width: CGFloat) -> some View {
        if Calendar.current.isDateInToday(vm.day) {
            let yy = y(of: Date())
            if yy > 0 && yy < CGFloat(totalHours) * hourHeight {
                Rectangle().fill(Color.red).frame(width: width, height: 1)
                    .offset(x: timeColWidth, y: yy)
                Circle().fill(Color.red).frame(width: 7, height: 7)
                    .offset(x: timeColWidth - 3, y: yy - 3)
            }
        }
    }
}
