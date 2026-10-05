課表截圖匯入的自動測試（需連得到家裡的模型）。
1. `swiftc -o gen gen.swift && ./gen` 畫出 6 組合成課表截圖與標準答案（manifest.json）。
2. `python3 run.py` 把圖縮成 1600px、用 App 的提示呼叫模型（提示內容複製自 LLMClient.parseCourses，路徑 /tmp/p6.txt）。
3. `swiftc -o score ../../AutoCal/Services/Course.swift ../../AutoCal/Services/AppConfig.swift score.swift && ./score` 用 App 真正的合併邏輯算分。

量測版（App 現在的主要做法，不用模型）：
`swiftc -O -o geo ../../AutoCal/Services/TimetableGeometry.swift geo/main.swift && ./geo 圖片.jpg 輸出.json`
輸出的 JSON 格式和模型相同，可以直接丟給上面的 score.swift 計分。
