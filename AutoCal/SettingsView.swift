import SwiftUI

/// 設定：搜尋金鑰、模型後端。全部存在本機 UserDefaults。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("brave.apiKey") private var braveKey = ""
    @AppStorage("llm.baseURL") private var llmBaseURL = ""
    @AppStorage("llm.model") private var llmModel = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        WallpaperSettingsView()
                    } label: {
                        Label("鎖定畫面桌布", systemImage: "iphone.gen3")
                    }
                } footer: {
                    Text("把今天的課堂、行程與空堂畫成鎖定畫面桌布。")
                }

                ClassReminderSection()

                Section {
                    SecureField("貼上 Brave 搜尋金鑰", text: $braveKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("網路搜尋（Brave API）")
                } footer: {
                    Text("到 api-dashboard.search.brave.com 申請免費金鑰。只存在這支手機，不會上傳。")
                }

                Section {
                    TextField("模型 API 位址", text: $llmBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型名稱", text: $llmModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("模型後端")
                } footer: {
                    Text("留空則使用預設：家中 192.168.0.45 優先，連不到時自動改用 3090。填了自訂位址就只用那一台。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
