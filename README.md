# LazyNote

把**截圖、一句話或查到的活動**，自動變成 iOS 行事曆行程與提醒事項，不用手動輸入時間。

## 這是什麼

一個個人用的 iOS App。核心流程：

```
任何輸入 → LLM 解析成結構化資料 → 你確認（可編輯）→ 寫進行事曆 / 提醒事項
```

輸入方式：
- **打字 / 語音**：例如「下週三晚上七點跟小明吃火鍋」
- **截圖分享**：在任何 App 按分享 → 選 LazyNote，自動辨識海報、票券、對話裡的時間地點

## 技術

- SwiftUI + EventKit（寫入系統行事曆與提醒事項）
- 專案用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理：改完程式或設定後，跑 `xcodegen generate` 重建 `.xcodeproj`
- 解析後端：家中 GPU 伺服器上的 vLLM / llama.cpp（OpenAI 相容 API），設定在 `LazyNote/Services/AppConfig.swift`

## 開發

```bash
xcodegen generate      # 產生 LazyNote.xcodeproj
open LazyNote.xcodeproj # 用 Xcode 開啟
```

## 結構

```
LazyNote/              主 App
├── ContentView.swift  打字/語音輸入畫面
├── ItemCard.swift     確認卡片（App 與擴充功能共用）
├── Models/            ParsedItem 等資料模型
└── Services/          LLMClient（解析）、EventStoreWriter（寫入）、AppConfig（後端設定）
LazyNoteShare/         Share Extension（截圖入口）
project.yml            XcodeGen 專案定義
```
