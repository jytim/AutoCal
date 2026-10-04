import SwiftUI

extension View {
    /// 淡色底加左邊一條粗色條的卡片。底下先墊一層不透明的底色，疊在一起時後面的卡片不會透出來。
    func tintedCard(_ color: Color, radius: CGFloat, bar: CGFloat = 4) -> some View {
        self
            .background(
                ZStack {
                    Color(.systemBackground)
                    color.opacity(0.17)
                }
            )
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: bar)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(color.opacity(0.35), lineWidth: 0.6))
    }
}
