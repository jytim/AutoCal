import SwiftUI

/// 設定：搜尋金鑰、模型後端、校園行事曆網址。全部存在本機 UserDefaults。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("brave.apiKey") private var braveKey = ""
    @AppStorage("llm.baseURL") private var llmBaseURL = ""
    @AppStorage("llm.model") private var llmModel = ""
    @AppStorage("campus.icsURL") private var campusURL = ""

    var body: some View {
        NavigationStack {
            Form {
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
                    TextField("校園行事曆 ICS 網址", text: $campusURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("校園行事曆")
                } footer: {
                    Text("留空則使用內建的台科大行事曆。每學年更新時可在此換成新網址。")
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
                    Text("留空則使用預設（家中 3090）。")
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
