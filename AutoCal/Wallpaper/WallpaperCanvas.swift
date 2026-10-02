import SwiftUI

/// 要被畫成鎖定畫面桌布的那一整張圖。
/// 上方約三分之一留給系統的時鐘與小工具，下方留給手電筒/相機按鈕。
struct WallpaperCanvas: View {
    let content: WallpaperContent

    static let topFraction: CGFloat = 0.355
    static let bottomFraction: CGFloat = 0.125
    static let sidePadding: CGFloat = 20

    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayText: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d EEEE"; return f
    }()

    /// 列表區可用的高度（給 WallpaperContentBuilder 排版用）。
    static func listBudget(forHeight h: CGFloat) -> CGFloat {
        let headerAndChips: CGFloat = 52
        let tomorrowStrip: CGFloat = 54
        return h * (1 - topFraction - bottomFraction) - headerAndChips - tomorrowStrip
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(red: 0.05, green: 0.06, blue: 0.09)
                VStack(alignment: .leading, spacing: WallpaperContentBuilder.rowSpacing) {
                    header
                    ForEach(content.rows) { rowView($0) }
                    if content.rows.isEmpty { emptyState }
                    Spacer(minLength: 0)
                    tomorrowStrip
                }
                .padding(.horizontal, Self.sidePadding)
                .padding(.top, geo.size.height * Self.topFraction)
                .padding(.bottom, geo.size.height * Self.bottomFraction)
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - 區塊

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Self.dayText.string(from: content.day))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(content.isToday ? "更新 \(Self.hm.string(from: content.generatedAt))" : "預覽")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if !content.chips.isEmpty {
                Text("全天：" + content.chips.joined(separator: "・"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            if !content.hasCalendarAccess {
                Text("沒有行事曆權限，只顯示課堂")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func rowView(_ row: WallpaperRow) -> some View {
        switch row {
        case .item(let it, let isNow, let isFirst):
            itemCard(it, isNow: isNow, big: isFirst)
        case .free(let s, let e):
            freeRow(s, e)
        case .more(let n):
            Text("還有 \(n) 件…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: WallpaperContentBuilder.moreHeight)
        }
    }

    private func itemCard(_ it: WallpaperItem, isNow: Bool, big: Bool) -> some View {
        let time = "\(Self.hm.string(from: it.start))–\(Self.hm.string(from: it.end))"
        let detail = [time, it.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(it.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                if big {
                    Text(isNow ? "進行中" : (content.isToday ? "下一件事" : "第一件事"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(it.color)
                }
                Text(it.title)
                    .font(.system(size: big ? 22 : 16, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: big ? 14 : 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: big ? WallpaperContentBuilder.bigCardHeight : WallpaperContentBuilder.itemHeight)
        .background(it.color.opacity(big ? 0.30 : 0.18))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(it.color.opacity(isNow ? 0.95 : 0.4), lineWidth: isNow ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func freeRow(_ s: Date, _ e: Date) -> some View {
        let mins = Int(e.timeIntervalSince(s) / 60)
        let dur = mins >= 60 ? (mins % 60 == 0 ? "\(mins / 60)h" : "\(mins / 60)h\(mins % 60)") : "\(mins)m"
        return HStack {
            Text("空堂 \(dur)")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text("\(Self.hm.string(from: s))–\(Self.hm.string(from: e))")
                .font(.system(size: 11))
        }
        .foregroundStyle(Color.green.opacity(0.9))
        .padding(.horizontal, 12)
        .frame(height: WallpaperContentBuilder.freeHeight)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.green.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.isToday ? "今天沒有更多行程" : "這天沒有行程")
                .font(.system(size: 20, weight: .bold))
            Text("好好休息")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 16)
    }

    private var tomorrowStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.isToday ? "明天" : "隔天")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            if content.tomorrow.isEmpty {
                Text("沒有行程")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(content.tomorrow) { it in
                    HStack(spacing: 6) {
                        Circle().fill(it.color).frame(width: 6, height: 6)
                        Text(Self.hm.string(from: it.start))
                            .font(.system(size: 12, weight: .semibold))
                        Text(it.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}
