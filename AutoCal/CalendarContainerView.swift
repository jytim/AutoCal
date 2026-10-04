import SwiftUI

/// 行事曆：日、週、月三個尺度放在同一頁，用上方的切換列來換。
/// 三個尺度共用「目前日期」——在月看到 10/8，切到週就是那一週，切到日就是 10/8。
struct CalendarContainerView: View {
    enum Mode: String, CaseIterable { case day, week, month
        var title: String { switch self { case .day: return "日"; case .week: return "週"; case .month: return "月" } }
    }

    @AppStorage("ui.calMode") private var modeRaw = Mode.day.rawValue
    @StateObject private var dayVM = DayViewModel()
    @StateObject private var weekVM = TimetableViewModel()
    @StateObject private var monthVM = MonthViewModel()

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .day }

    var body: some View {
        VStack(spacing: 0) {
            Picker("檢視", selection: Binding(get: { mode }, set: { switchTo($0) })) {
                ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            switch mode {
            case .day:
                DayView(vm: dayVM)
            case .week:
                TimetableView(onSelectDay: { day in switchTo(.day, anchor: day) }, vm: weekVM)
            case .month:
                MonthView(vm: monthVM, onSelectDay: { day in switchTo(.day, anchor: day) })
            }
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
