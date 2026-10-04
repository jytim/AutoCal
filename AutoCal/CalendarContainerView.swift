import SwiftUI

/// 行事曆：日、週、月三個尺度放在同一頁，用上方的切換列來換。
/// 三個尺度共用「目前日期」——在月看到 10/8，切到週就是那一週，切到日就是 10/8。
struct CalendarContainerView: View {
    enum Mode: String, CaseIterable { case day, week, month
        var title: String { switch self { case .day: return "日"; case .week: return "週"; case .month: return "月" } }
    }

    @AppStorage("ui.calMode") private var modeRaw = Mode.day.rawValue
    @AppStorage("ui.showWeekView") private var showWeekView = true
    @StateObject private var dayVM = DayViewModel()
    @StateObject private var weekVM = TimetableViewModel()
    @StateObject private var monthVM = MonthViewModel()

    /// 切換列：日｜週｜月。設定裡關掉「顯示週檢視」時只剩日｜月。
    private var pickerModes: [Mode] { showWeekView ? [.day, .week, .month] : [.day, .month] }
    private var mode: Mode {
        let m = Mode(rawValue: modeRaw) ?? .day
        return (m == .week && !showWeekView) ? .day : m
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("檢視", selection: Binding(get: { mode }, set: { switchTo($0) })) {
                ForEach(pickerModes, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            Group {
            switch mode {
            case .day:
                DayView(vm: dayVM, onTapTitle: { switchTo(.month) })
            case .week:
                TimetableView(onSelectDay: { day in switchTo(.day, anchor: day) }, vm: weekVM)
            case .month:
                MonthView(vm: monthVM, onSelectDay: { day in switchTo(.day, anchor: day) })
            }
            }
            // 左右滑動換日／週／月（像 Apple 行事曆）：只在明顯橫向、距離夠長時才算，不干擾上下捲動與點擊
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    guard !GestureGuard.axisDragging, abs(dx) > 70, abs(dx) > abs(dy) * 1.8 else { return }
                    step(dx < 0 ? 1 : -1)
                })
        }
    }

    private func step(_ n: Int) {
        switch mode {
        case .day: dayVM.shift(by: n)
        case .week: weekVM.shiftWeek(by: n)
        case .month: monthVM.shiftMonth(by: n)
        }
    }

    /// 切換尺度：把目前看的日期帶到新的尺度。
    private func switchTo(_ new: Mode, anchor: Date? = nil) {
        let date = anchor ?? currentAnchor()
        switch new {
        case .day: dayVM.select(date)
        case .week: weekVM.goTo(date: date)
        case .month: monthVM.goTo(date: date)
        }
        modeRaw = new.rawValue
    }

    /// 目前這個尺度「正在看的日期」：週、月若包含今天就用今天，否則用該週／月的起點。
    private func currentAnchor() -> Date {
        let cal = Calendar.current
        let today = Date()
        switch mode {
        case .day: return dayVM.day
        case .week:
            let end = cal.date(byAdding: .day, value: 7, to: weekVM.weekStart) ?? weekVM.weekStart
            return (weekVM.weekStart <= today && today < end) ? today : weekVM.weekStart
        case .month:
            return cal.isDate(today, equalTo: monthVM.monthStart, toGranularity: .month) ? today : monthVM.monthStart
        }
    }
}
