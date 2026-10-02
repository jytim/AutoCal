import SwiftUI

@MainActor
final class InputViewModel: ObservableObject {
    @Published var text = ""
    @Published var items: [ParsedItem] = []
    @Published var isParsing = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let llm = LLMClient()
    private let writer = EventStoreWriter()
    private let campus = CampusCalendarService()
    private let web = WebSearchService()
    private let checker = ConflictChecker()

    func parse() async {
        await run(emptyMessage: { _ in "沒有辨識到任何行程或待辦。" }) { [llm] q in
            try await llm.parse(text: q)
        }
    }

    /// 把輸入當成查詢，去校園行事曆找對應的事件。
    func searchCampus() async {
        await run(emptyMessage: { "行事曆裡找不到「\($0)」相關的事件。" }) { [campus] q in
            try await campus.search(query: q)
        }
    }

    /// 把輸入當成查詢，上網搜尋活動。
    func searchWeb() async {
        await run(emptyMessage: { "網路上找不到「\($0)」的明確活動資訊。" }) { [web] q in
            try await web.search(query: q)
        }
    }

    /// 使用者改過時間後，重新檢查衝突。
    func recheckConflicts() async {
        isParsing = true
        items = await checker.annotate(items)
        isParsing = false
    }

    /// 三種輸入共用：取得項目 → 檢查衝突 → 顯示確認卡片。
    private func run(emptyMessage: (String) -> String,
                     fetch: (String) async throws -> [ParsedItem]) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isParsing = true
        errorMessage = nil
        successMessage = nil
        do {
            items = await checker.annotate(try await fetch(trimmed))
            if items.isEmpty { errorMessage = emptyMessage(trimmed) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isParsing = false
    }

    /// 還有衝突沒讓使用者選擇處理方式，不能加入（AI 不會替使用者決定）。
    var hasUndecidedConflicts: Bool {
        items.contains { $0.isSelected && $0.resolution == .undecided }
    }

    func save() async {
        errorMessage = nil
        do {
            let r = try await writer.write(ConflictChecker.applyResolutions(items))
            var parts: [String] = []
            if r.events > 0 { parts.append("\(r.events) 個行程") }
            if r.reminders > 0 { parts.append("\(r.reminders) 個待辦") }
            successMessage = parts.isEmpty ? "沒有選取任何項目" : "已加入 " + parts.joined(separator: "、")
            if r.failures.isEmpty {
                items = []
                text = ""
            } else {
                errorMessage = r.failures.joined(separator: "\n")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = InputViewModel()
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputCard

                    if let msg = vm.successMessage {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if let err = vm.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }

                    if !vm.items.isEmpty {
                        HStack {
                            Text("確認要加入的項目")
                                .font(.headline)
                            Spacer()
                            Button {
                                Task { await vm.recheckConflicts() }
                            } label: {
                                Label("重新檢查衝突", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.footnote)
                            }
                            .disabled(vm.isParsing)
                        }
                        ForEach($vm.items) { $item in
                            ItemCard(item: $item)
                        }
                        if vm.hasUndecidedConflicts {
                            Label("請先為每個衝突選擇處理方式，才能加入", systemImage: "hand.raised.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Button {
                            Task { await vm.save() }
                        } label: {
                            Label("加入行事曆 / 提醒事項", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(vm.hasUndecidedConflicts)
                    }
                }
                .padding()
            }
            .navigationTitle("AutoCal")
            // 點空白處或往下滑都收起鍵盤
            .onTapGesture { inputFocused = false }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("完成") { inputFocused = false }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("輸入一句話，例如：下週三晚上七點跟小明吃火鍋")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("想安排的行程或待辦…", text: $vm.text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
            if vm.isParsing {
                ProgressView().frame(maxWidth: .infinity).controlSize(.large)
            } else {
                Button {
                    Task { await vm.parse() }
                } label: {
                    Label("解析", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.text.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    Task { await vm.searchCampus() }
                } label: {
                    Label("查校園行事曆", systemImage: "graduationcap")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.text.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    Task { await vm.searchWeb() }
                } label: {
                    Label("搜尋網路活動", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

#Preview {
    ContentView()
}
