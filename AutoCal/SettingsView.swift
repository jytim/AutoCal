import SwiftUI

/// 設定：搜尋金鑰、模型後端。全部存在本機 UserDefaults。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("brave.apiKey") private var braveKey = ""
    @AppStorage("llm.baseURL") private var llmBaseURL = ""
    @AppStorage("llm.model") private var llmModel = ""
    @AppStorage(EventColor.followKey) private var followCalendarColor = true
    @AppStorage("ui.showTimetable") private var showTimetable = true

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

                Section {
                    Toggle("顯示課表分頁", isOn: $showTimetable)
                    NavigationLink {
                        CourseManageView()
                    } label: {
                        Label("課堂管理", systemImage: "books.vertical")
                    }
                } footer: {
                    Text("不是學生可以關掉課表分頁。課堂資料仍然保留，衝突偵測、上課提醒、鎖定畫面桌布都照常使用；要新增或修改課堂就從「課堂管理」進去。")
                }

                Section {
                    Toggle("行程顏色跟隨行事曆", isOn: $followCalendarColor)
                } footer: {
                    Text("開啟：行程用 Apple 行事曆裡該行事曆的顏色（到「行事曆」App 改顏色，這裡就跟著變）。關閉：依標題自動配色。課堂的顏色在編輯課堂時自己選。")
                }

                ClassReminderSection()

                Section {
                    NavigationLink {
                        ShareLogView()
                    } label: {
                        Label("分享診斷紀錄", systemImage: "stethoscope")
                    }
                } footer: {
                    Text("從別的 App 分享給 AutoCal 閃退時，這裡會留下它最後做到哪一步，可以複製給開發者。")
                }

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
                    Text("留空則使用預設：家中 <內網主機A> 優先，連不到時自動改用 3090。填了自訂位址就只用那一台。")
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
