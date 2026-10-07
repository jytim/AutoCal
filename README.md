# Just Add 記吧

（程式內部代號仍叫 AutoCal：資料夾、scheme 與 bundle id 沿用舊名。）

把**截圖、一句話或查到的活動**，自動變成 iOS 行事曆行程與提醒事項，不用手動輸入時間。

## 這是什麼

一個個人用的 iOS App。核心流程：

```
任何輸入 → LLM 解析成結構化資料 → 你確認（可編輯）→ 寫進行事曆 / 提醒事項
```

輸入方式：
- **打字 / 語音**：例如「下週三晚上七點跟小明吃火鍋」
- **截圖分享**：在任何 App 按分享 → 選「記吧」，自動辨識海報、票券、對話裡的時間地點

## 技術

- SwiftUI + EventKit（寫入系統行事曆與提醒事項）
- 專案用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理：改完程式或設定後，跑 `xcodegen generate` 重建 `.xcodeproj`
- 解析後端：自架模型（OpenAI 相容 API）經 LiteLLM 閘道與 Cloudflare 隧道對外提供，App 以邀請金鑰存取，位址設定在 `AutoCal/Services/AppConfig.swift`；網路搜尋由同一台伺服器代為呼叫，搜尋金鑰不放在手機
- 課表截圖匯入不經過模型：用 iOS 內建文字辨識加像素分析，在手機上離線完成

## 開發

```bash
xcodegen generate      # 產生 AutoCal.xcodeproj
open AutoCal.xcodeproj # 用 Xcode 開啟
```

## 結構

```
AutoCal/              主 App
├── ContentView.swift  打字/語音輸入畫面
├── ItemCard.swift     確認卡片（App 與擴充功能共用）
├── Models/            ParsedItem 等資料模型
└── Services/          LLMClient（解析）、EventStoreWriter（寫入）、AppConfig（後端設定）
AutoCalShare/         Share Extension（截圖入口）
project.yml            XcodeGen 專案定義
```

>my first git practice

個人專案開發中
