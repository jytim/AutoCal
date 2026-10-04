import SwiftUI

/// 設定 → 分享診斷紀錄：分享選單閃退時，看它最後做到哪一步。
struct ShareLogView: View {
    @State private var text = ShareLog.read()

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "還沒有紀錄。從別的 App 分享一次內容給 AutoCal 後，再回來看。" : text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("分享診斷紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { text = ShareLog.read() } label: { Image(systemName: "arrow.clockwise") }
                ShareLink(item: text.isEmpty ? "（空）" : text)
                Button(role: .destructive) { ShareLog.clear(); text = "" } label: { Image(systemName: "trash") }
            }
        }
    }
}
