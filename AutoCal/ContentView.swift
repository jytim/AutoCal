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

    func parse() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isParsing = true
        errorMessage = nil
        successMessage = nil
        do {
            items = try await llm.parse(text: trimmed)
            if items.isEmpty { errorMessage = "沒有辨識到任何行程或待辦。" }
        } catch {
            errorMessage = error.localizedDescription
        }
        isParsing = false
    }

    func save() async {
        errorMessage = nil
        do {
            let r = try await writer.write(items)
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
                        Text("確認要加入的項目")
                            .font(.headline)
                        ForEach($vm.items) { $item in
                            ItemCard(item: $item)
                        }
                        Button {
                            Task { await vm.save() }
                        } label: {
                            Label("加入行事曆 / 提醒事項", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .navigationTitle("AutoCal")
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
            Button {
                Task { await vm.parse() }
            } label: {
                if vm.isParsing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("解析", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(vm.isParsing || vm.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

#Preview {
    ContentView()
}
