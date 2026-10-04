import SwiftUI

/// 辨識時的假進度條：沒有任何依據，只是會一直往前走（越接近尾端越慢，不會超過 94%），
/// 並且隨機輪播 emoji 加冷知識，讓等待不那麼無聊。
struct FakeProgressView: View {
    var label = "正在辨識…"

    @State private var start = Date()
    @State private var tips = FakeProgressView.allTips.shuffled()
    @State private var emojis = FakeProgressView.allEmojis.shuffled()

    /// 每則冷知識顯示幾秒。
    private let secondsPerTip = 6.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            // 約 8 秒到 60%、18 秒到 85%，之後幾乎停在 94% 附近等結果
            let progress = 0.94 * (1 - exp(-t / 9))
            let index = Int(t / secondsPerTip)

            VStack(spacing: 14) {
                Text(emojis[index % emojis.count])
                    .font(.system(size: 54))
                    .id("e\(index)")
                    .transition(.scale.combined(with: .opacity))
                Text(tips[index % tips.count])
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 66, alignment: .top)
                    .id("t\(index)")
                    .transition(.opacity)
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(label)
                        Spacer()
                        Text("\(Int(progress * 100))%").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: index)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 內容

    static let allEmojis = ["🐙", "🍯", "🍌", "⚡️", "🪼", "🦥", "🪐", "👀", "🦈", "🐧", "🦋", "🐱", "🌈",
                            "🦦", "🐼", "🦒", "🐻‍❄️", "🌏", "💻", "📬", "🕐", "🐨", "🦉", "🍓"]

    static let allTips = [
        "章魚有三顆心臟。",
        "蜂蜜幾乎不會壞，密封好可以放非常久。",
        "香蕉在植物學上算漿果，草莓反而不是。",
        "閃電的溫度可以比太陽表面還高。",
        "水母沒有大腦、沒有心臟，也沒有骨頭。",
        "金星的一天比它的一年還要長。",
        "鯊魚出現在地球上的時間，比樹還早。",
        "蝴蝶是用腳來嚐味道的。",
        "貓的鼻紋跟人的指紋一樣，每隻都不同。",
        "袋熊的便便是方塊形的。",
        "彩虹其實是完整的圓形，我們在地面上通常只看到上半圈。",
        "海獺睡覺時會牽著手，免得漂散。",
        "長頸鹿和人類一樣，脖子都是七節頸椎。",
        "北極熊的皮膚其實是黑色的。",
        "夏威夷每年大約往西北移動 7 公分。",
        "世界上第一個網站在 1991 年上線。",
        "第一封電子郵件是在 1971 年寄出的。",
        "地球自轉一圈其實大約是 23 小時 56 分。",
        "企鵝裡有些種類，求偶時會送對方一顆石頭。",
        "人平均一分鐘眨眼約 15 到 20 次。",
        "大貓熊一天可以吃掉十幾公斤的竹子。",
        "樹懶大約一個星期才排便一次。"
    ]
}
