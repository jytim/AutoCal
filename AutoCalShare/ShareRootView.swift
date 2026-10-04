import SwiftUI

/// Share Extension 的主畫面：辨識截圖 → 顯示可編輯確認卡片 → 寫入行事曆/提醒事項。
struct ShareRootView: View {
    let input: SharedInput
    let onClose: () -> Void

    @State private var items: [ParsedItem] = []
    @State private var phase: Phase = .loading
    @State private var message: String?

    enum Phase { case loading, review, done, failed }

    private let llm = LLMClient()
    private let writer = EventStoreWriter()
    private let checker = ConflictChecker()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("AutoCal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { onClose() }
                    }
                }
        }
        .task { await analyze() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            FakeProgressView(label: loadingText)
        case .review:
            ScrollView {
                ReviewSection(items: $items, isBusy: false) {
                    Task { items = await checker.annotate(items) }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                ReviewAddBar(items: items) { Task { await save() } }
            }
        case .done:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle).foregroundStyle(.green)
                Text(message ?? "已加入").font(.headline)
                Button("完成") { onClose() }.buttonStyle(.borderedProminent)
            }
        case .failed:
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text(message ?? "辨識失敗").multilineTextAlignment(.center)
                    .font(.footnote).foregroundStyle(.secondary)
                Button("關閉") { onClose() }.buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private var hasUndecidedConflicts: Bool {
        items.contains { $0.isSelected && $0.resolution == .undecided }
    }

    private var loadingText: String {
        if case .text = input { return "正在辨識文字…" }
        return "正在辨識截圖…"
    }

    private func analyze() async {
        ShareLog.write("開始辨識")
        do {
            let result: [ParsedItem]
            switch input {
            case .image(let data, let mime):
                result = try await llm.parse(imageData: data, mimeType: mime)
            case .text(let text):
                result = try await llm.parse(text: text)
            case .none:
                message = "找不到可辨識的內容"; phase = .failed; return
            }
            ShareLog.write("模型回傳 \(result.count) 筆")
            if result.isEmpty {
                message = "沒有找到行程或待辦"; phase = .failed
            } else {
                ShareLog.write("檢查衝突中")
                items = await checker.annotate(result); phase = .review
                ShareLog.write("顯示確認畫面")
            }
        } catch {
            ShareLog.write("辨識失敗：\(error.localizedDescription)")
            message = error.localizedDescription; phase = .failed
        }
    }

    private func save() async {
        do {
            let r = try await writer.write(ConflictChecker.applyResolutions(items))
            var parts: [String] = []
            if r.events > 0 { parts.append("\(r.events) 個行程") }
            if r.reminders > 0 { parts.append("\(r.reminders) 個待辦") }
            message = parts.isEmpty ? "沒有選取任何項目" : "已加入 " + parts.joined(separator: "、")
            if r.failures.isEmpty {
                phase = .done
            } else {
                message = r.failures.joined(separator: "\n"); phase = .failed
            }
        } catch {
            message = error.localizedDescription; phase = .failed
        }
    }
}
