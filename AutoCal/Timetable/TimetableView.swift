import SwiftUI

/// 課表式的一週時間塊檢視：事件是方塊，週一到週五的空檔標成「空堂」。
struct TimetableView: View {
    @StateObject private var vm = TimetableViewModel()
    @State private var selected: TimetableEvent?

    private let hourHeight: CGFloat = 46
    private let timeColWidth: CGFloat = 34
    private let headerHeight: CGFloat = 44

    private var totalHours: Int { TimetableViewModel.endHour - TimetableViewModel.startHour }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d"
        return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "E"
        return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekBar
                if vm.accessDenied {
                    Spacer()
                    Label("需要行事曆權限才能顯示課表，請到「設定」開啟。", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                } else {
                    GeometryReader { geo in
                        let colWidth = (geo.size.width - timeColWidth) / 7
                        VStack(spacing: 0) {
                            dayHeader(colWidth: colWidth)
                            ScrollView {
                                grid(colWidth: colWidth)
                                    .frame(height: CGFloat(totalHours) * hourHeight, alignment: .topLeading)
                                    .padding(.bottom, 80)
                            }
                        }
                    }
                }
            }
            .navigationTitle("課表")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await vm.load() } }
            .sheet(item: $selected) { event in
                EventDetailSheet(event: event)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 週切換列

    private var weekBar: some View {
        HStack {
            Button { vm.shiftWeek(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text("\(Self.monthDay.string(from: vm.weekStart)) – \(Self.monthDay.string(from: vm.days.last ?? vm.weekStart))")
                    .font(.subheadline.bold())
                Button("回到本週") { vm.goToThisWeek() }
                    .font(.caption)
            }
            Spacer()
            Button { vm.shiftWeek(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 星期標頭

    private func dayHeader(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColWidth)
            ForEach(vm.days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 1) {
                    Text(Self.weekday.string(from: day))
                        .font(.caption2)
                    Text(Self.monthDay.string(from: day))
                        .font(.caption2.bold())
                }
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: colWidth, height: headerHeight - 8)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(height: headerHeight)
    }

    // MARK: - 格子本體

    private func grid(colWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // 小時橫線與標籤
            ForEach(0..<totalHours, id: \.self) { i in
                let y = CGFloat(i) * hourHeight
                Text(String(format: "%02d", TimetableViewModel.startHour + i))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: timeColWidth - 4, alignment: .trailing)
                    .offset(x: 0, y: y - 6)
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 0.5)
                    .padding(.leading, timeColWidth)
                    .offset(y: y)
            }

            // 每天一欄：空堂在底、事件方塊在上
            ForEach(Array(vm.days.enumerated()), id: \.offset) { index, day in
                let x = timeColWidth + CGFloat(index) * colWidth

                if vm.isWeekday(day) {
                    ForEach(vm.freeSlots(on: day)) { slot in
                        freeBlock(slot, colWidth: colWidth)
                            .offset(x: x, y: yPosition(of: slot.start))
                    }
                }

                let dayEvents = vm.events(on: day)
                let lanes = vm.lanes(for: dayEvents)
                ForEach(dayEvents) { e in
                    // 撞時段的行程做成「疊在一起的卡片」：後面的往右露出一點邊、微微歪斜，
                    // 比對半切成窄條寬，字才放得下。
                    let info = lanes[e.id] ?? (0, 1)
                    let stagger: CGFloat = info.count > 1 ? min(colWidth * 0.22, 12) : 0
                    let cardWidth = colWidth - stagger * CGFloat(info.count - 1)
                    let tilt: Double = info.count > 1 ? (info.lane % 2 == 0 ? -1.6 : 1.6) : 0
                    eventBlock(e, width: cardWidth)
                        .rotationEffect(.degrees(tilt))
                        .shadow(color: .black.opacity(info.count > 1 ? 0.28 : 0.1),
                                radius: 1.5, x: 0, y: 1)
                        .offset(x: x + stagger * CGFloat(info.lane),
                                y: yPosition(of: e.start))
                        .zIndex(Double(info.lane))
                        .onTapGesture { selected = e }
                }
            }

            // 現在時間紅線（只在本週、且在顯示範圍內）
            nowLine(colWidth: colWidth)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func yPosition(of date: Date) -> CGFloat {
        let c = Calendar.current
        let minutes = c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
        let rel = CGFloat(minutes - TimetableViewModel.startHour * 60) / 60
        return max(rel, 0) * hourHeight
    }

    private func eventBlock(_ e: TimetableEvent, width: CGFloat) -> some View {
        let top = yPosition(of: e.start)
        let bottom = min(yPosition(of: e.end), CGFloat(totalHours) * hourHeight)
        let height = max(bottom - top, 20)
        return VStack(alignment: .leading, spacing: 1) {
            Text(e.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(height > 44 ? 3 : 1)
            if height > 34 {
                Text(Self.hm.string(from: e.start))
                    .font(.system(size: 9))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: width - 2, height: height - 1, alignment: .topLeading)
        .background(e.color)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.7), lineWidth: 0.8))
        .padding(.leading, 1)
    }

    private func freeBlock(_ slot: FreeSlot, colWidth: CGFloat) -> some View {
        let height = CGFloat(slot.duration / 3600) * hourHeight
        let hours = Int(slot.duration / 3600)
        let mins = Int(slot.duration.truncatingRemainder(dividingBy: 3600) / 60)
        let label = hours > 0 ? (mins > 0 ? "\(hours)h\(mins)" : "\(hours)h") : "\(mins)m"
        return RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.green.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .background(Color.green.opacity(0.07).clipShape(RoundedRectangle(cornerRadius: 5)))
            .overlay(alignment: .top) {
                if height > 30 {
                    VStack(spacing: 0) {
                        Text("空堂").font(.system(size: 9, weight: .semibold))
                        Text(label).font(.system(size: 9))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.top, 3)
                }
            }
            .frame(width: colWidth - 2, height: height - 1)
            .padding(.leading, 1)
    }

    @ViewBuilder
    private func nowLine(colWidth: CGFloat) -> some View {
        let now = Date()
        if let idx = vm.days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: now) }) {
            let y = yPosition(of: now)
            if y > 0 && y < CGFloat(totalHours) * hourHeight {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: colWidth * 7 + 0, height: 1)
                    .offset(x: timeColWidth + 0, y: y)
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: timeColWidth + CGFloat(idx) * colWidth - 3, y: y - 3)
            }
        }
    }
}

// MARK: - 詳情

private struct EventDetailSheet: View {
    let event: TimetableEvent
    @Environment(\.dismiss) private var dismiss

    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d (E) HH:mm"
        return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title).font(.headline)
                    Label("\(Self.full.string(from: event.start)) – \(Self.hm.string(from: event.end))",
                          systemImage: "clock")
                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                    }
                }
                if let notes = event.notes, !notes.isEmpty {
                    Section("備註 / AI 決策紀錄") {
                        Text(notes).font(.footnote)
                    }
                }
            }
            .navigationTitle("行程詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
