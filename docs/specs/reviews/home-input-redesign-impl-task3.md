# 新增頁改版 任務 3 實作審查

日期：2026-10-11　規格：home-input-redesign.md v3.2

## 範圍
只改 `AutoCal/ContentView.swift`：「解析」改用 PrimaryGlassButton、「搜尋網路活動」改用 SecondaryGlassButton；停用條件改為 `.whitespacesAndNewlines`（含純換行）；解析中狀態（FakeProgressView）不變。

## 過程
1. luna 第一版建置失敗：`'async' call in a function that does not support concurrency`（action 為 `() -> Void`，不能直接 await）。luna 無法建置，由 Claude 建置發現，錯誤原文退回 luna，改為 `Task { await ... }`。
2. Claude 從截圖發現：SecondaryGlassButton 的 `.foregroundStyle(.primary)` 蓋掉停用變淡效果，空白時看起來仍可用。退回 luna，加 `@Environment(\.isEnabled)`，停用時 `Color.primary.opacity(0.35)`。
3. 建置成功；淺色空白、淺色有字、深色有字截圖已給使用者（iOS 26.5 模擬器）。

## 結論
程式符合任務 3 範圍，未動其他檔案。未驗證：iOS 17 退路、解析中進度條、Dynamic Type、iPad、降低透明度——交任務 4a～4d。
