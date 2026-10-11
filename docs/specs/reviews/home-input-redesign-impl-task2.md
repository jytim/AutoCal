# 實作審查：home-input-redesign 任務 2（Claude，2026-10-07）

對象：luna 實作的任務 2（`AutoCal/ContentView.swift` +15／−6，未提交）。
結論：**程式符合規格，建置已通過；視覺方向待使用者確認**（見下）。

## 過程
1. luna 第一版：`TextField(text:prompt:axis:)` 缺少標題參數，Claude 在 Xcode 26 實際建置時失敗（luna 無法建置，只做了語法檢查）。
2. Claude 退回給 luna 並附完整錯誤，luna 補上標題；第二版建置成功。Claude 沒有自己改程式。

## 對任務 2 範圍檢查
| 項目 | 結果 |
|---|---|
| 只改 `ContentView.swift`，沒有新增檔案 | 通過 |
| 系統背景、large 標題維持「Just Add 記吧」 | 通過 |
| 移除說明小字；輸入框 4–8 行、title3、plain、固定 accessibilityLabel、保留焦點 | 通過 |
| 玻璃面板只包輸入框，內距 20、最小高度 150、解析中與按鈕維持原樣 | 通過 |
| 其他（訊息、復原、ReviewSection、工具列、鍵盤完成、640 限制）未動 | 通過 |

## 視覺觀察（需要使用者決定）
1. **placeholder 太淡**：淺色與深色空白時，「下週三晚上七點跟小明吃火鍋」都幾乎看不清，對比不足。
2. **淺色模式玻璃面板很不明顯**：白底白面板，只靠極淡陰影；深色模式有邊線，較清楚。
3. **面板與下方按鈕風格不一致**：按鈕仍是舊的灰色樣式（任務 3 才改）。
4. 尚未驗證：點面板內距區（輸入框外 20pt）是否會誤收鍵盤（規格 §6 風險）、降低透明度／增加對比、Dynamic Type、iPad、iOS 17。

截圖：iOS 26.5 模擬器，淺色／深色 × 空白／有字。

## 追加修正（2026-10-11，使用者選 B）
luna 依使用者決定修正三處（僅 ContentView.swift）：placeholder 改 `Color.primary.opacity(0.45)`；GlassPanel 兩條路徑加 0.75pt `Color.primary.opacity(0.12)` 邊線（fallback 原邊線取代，不疊加）；淺色模式頁面背景改 `systemGroupedBackground`，深色維持 `systemBackground`。Claude 建置成功，淺／深色空白截圖已給使用者，使用者同意進任務 3。
