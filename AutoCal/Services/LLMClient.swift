import Foundation

/// 呼叫 3090 上的 llama.cpp（OpenAI 相容）端點，把自然語言解析成 ParsedItem。
struct LLMClient {

    enum LLMError: LocalizedError {
        case badResponse(String)
        case noContent
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let s): return "伺服器回應異常：\(s)"
            case .noContent: return "模型沒有回傳內容"
            case .decodeFailed(let s): return "無法解析模型輸出：\(s)"
            }
        }
    }

    /// 把一段中文（可含多個活動）解析成陣列。
    func parse(text: String, now: Date = Date()) async throws -> [ParsedItem] {
        // 先把「10.」改寫成「10點」，解析後再核對幾點、日期，對不上就在卡片上警告
        let cleaned = TimeSanity.normalize(text)
        let messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt(now: now)],
            ["role": "user", "content": cleaned]
        ]
        let parsed = try await send(messages: messages)
        let items = TimeSanity.correctRelativeDay(parsed, text: cleaned, now: now)
        return TimeSanity.annotate(items, text: cleaned, now: now)
    }

    /// 看截圖：把圖片（連同可選的補充文字）解析成陣列。
    /// 3090 上的 Qwen3-27B 有視覺能力，可直接吃 base64 圖片。
    func parse(imageData: Data, mimeType: String = "image/jpeg",
               hint: String? = nil, now: Date = Date()) async throws -> [ParsedItem] {
        let dataURI = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let userContent: [[String: Any]] = [
            ["type": "text",
             "text": hint ?? "這是一張截圖，請找出裡面所有的活動、時間、地點，轉成行程或待辦。"],
            ["type": "image_url", "image_url": ["url": dataURI]]
        ]
        let messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt(now: now)],
            ["role": "user", "content": userContent]
        ]
        return try await send(messages: messages, maxTokens: 1200)
    }

    /// 從網路搜尋結果（摘要 + 網頁內容）抽出符合查詢的活動。
    func extractFromWeb(query: String, snippets: String, pages: String,
                        now: Date = Date()) async throws -> [ParsedItem] {
        let system = """
        \(Self.systemPrompt(now: now))

        額外規則：以下是針對使用者查詢的網路搜尋結果（摘要與網頁內容）。
        請根據這些資料，抽出和查詢最相關的活動（日期、時間、地點），轉成上面的 JSON 陣列。
        - 只根據資料裡實際出現的資訊，不要自己編造日期。資料裡沒有明確日期就不要輸出那一筆。
        - 若只有日期沒有時間，allDay 設 true。
        - 把資料來源的重點（例如網址）放進 notes 以便查證（若 JSON 有 notes 欄位則填，否則省略）。
        - 找不到可靠的活動就回空陣列 []。
        """
        var user = "查詢：\(query)\n\n搜尋摘要：\n\(snippets)"
        if !pages.isEmpty { user += "\n\n網頁內容：\n\(pages)" }

        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
        return try await send(messages: messages, maxTokens: 1000)
    }

    // MARK: - 共用送出邏輯

    private func send(messages: [[String: Any]], maxTokens: Int = 800) async throws -> [ParsedItem] {
        let content = try await sendRaw(messages: messages, maxTokens: maxTokens)
        return try Self.decodeItems(from: content)
    }

    /// 送出並回傳模型的原始文字；依序嘗試後端，連不到就換下一台。
    private func sendRaw(messages: [[String: Any]], maxTokens: Int) async throws -> String {
        var lastError: Error = LLMError.badResponse("沒有可用的後端")
        for ep in AppConfig.endpoints {
            do {
                return try await sendOnce(to: ep, messages: messages, maxTokens: maxTokens)
            } catch let e as URLError {
                // 連不到這台（逾時、拒絕連線等）→ 試下一台備援
                lastError = e
            }
            // 其他錯誤（有連到但回應有問題）直接往外拋，不無謂重試
        }
        throw lastError
    }

    // MARK: - 課表截圖

    /// 看一張課表截圖，抽出每一門課（一門課一週上多次要分成多筆）。
    func parseCourses(imageData: Data, mimeType: String = "image/jpeg",
                      known: [CourseDraft] = []) async throws -> [CourseDraft] {
        let system = """
        你是課表辨識助理。使用者會給你一張課表截圖，請找出每一門課，輸出 JSON 陣列。
        每個元素的欄位：
        - name: 課程名稱（字串，去掉課號與老師名）
        - weekday: 星期，1=週一、2=週二、…、7=週日。請看課程方塊在「哪一欄」，對齊上方哪個星期標題
        - hasHeader: 布林。這張截圖裡你「真的看得到星期標題列」（週一、週二…）就填 true，看不到填 false
        - startPeriod: 這門課占用的第一個節次（字串，例如 "3" 或 "A"）
        - endPeriod: 這門課占用的最後一個節次（字串）
        - start / end: 只有當截圖上直接印了上課時間（"HH:mm"）才填；沒有就用 null
        - location: 教室；沒有就用 null

        規則：
        - 節次請仔細對照課程方塊的「上緣」和「下緣」各自對齊左邊哪一個節次數字。不要自己把節次換成時間。
        - 同一門課一週上好幾次（不同星期或不同時段），要拆成好幾筆。
        - 連續的節次合併成一筆（例如第 6、7 節 → startPeriod "6"，endPeriod "7"）。
        - 截圖可能只是整張課表的一部分（上下或左右被切掉）。課程方塊被切到邊緣時，只輸出你真的看得到的節次範圍，不要猜被切掉的部分。
        - 如果這張截圖看不到星期標題：
          · 若下面「已知的課」裡有同一門課，直接沿用它的星期（一門課在另一天也有的話，用方塊左右位置判斷是哪一欄）。
          · 否則不要亂猜，weekday 填 0（表示星期不明，由使用者自己選）。
        - 只根據截圖上真的看得到的課，不要編造。看不清楚的課就略過。
        只輸出 JSON 陣列本身，不要任何其他文字。
        """
        let dataURI = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "這是我的課表截圖，請把每一門課抽出來。"],
            ["type": "image_url", "image_url": ["url": dataURI]]
        ]
        var knownNote = ""
        if !known.isEmpty {
            knownNote = "\n\n已知的課（來自同一份課表的其他截圖，可當作線索）：\n" + known.map {
                "- \($0.name)：週\(Course.weekdayNames[max(0, min(6, $0.weekday - 1))])"
            }.joined(separator: "\n")
        }
        let text = try await sendRaw(messages: [
            ["role": "system", "content": system + knownNote],
            ["role": "user", "content": userContent]
        ], maxTokens: 2000)

        guard let a = text.firstIndex(of: "["), let b = text.lastIndex(of: "]"),
              let data = String(text[a...b]).data(using: .utf8) else {
            throw LLMError.decodeFailed(text)
        }
        do {
            // weekday = 0 代表星期不明，保留下來讓使用者在確認畫面自己選
            return try JSONDecoder().decode([CourseDraft].self, from: data)
                .filter { $0.startMinute != nil && $0.endMinute != nil && (0...7).contains($0.weekday) }
                .map { d in
                    // 看不到星期標題的截圖：星期是推測的，標記起來讓使用者確認
                    var d = d
                    if !d.hasHeader { d.weekdayGuessed = true }
                    return d
                }
        } catch {
            throw LLMError.decodeFailed("\(error)\n原文：\(text)")
        }
    }

    // MARK: - 衝突判斷

    struct ConcurrencyVerdict {
        let canOverlap: Bool
        let reason: String
    }

    /// 判斷新行程能不能和衝突的既有行程同時進行。
    func judgeConcurrency(item: ParsedItem,
                          conflicts: [ParsedItem.ConflictInfo]) async throws -> ConcurrencyVerdict {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.dateFormat = "M/d HH:mm"
        func range(_ s: Date?, _ e: Date?) -> String {
            guard let s else { return "時間未定" }
            return df.string(from: s) + (e.map { "–" + df.string(from: $0) } ?? "")
        }

        let system = """
        你是行程安排助理。判斷「新行程」能不能和「衝突的既有行程」同時進行。
        可以同時做的例子：通勤時聽 podcast、吃飯時線上聽講。
        不能同時做的例子：兩個需要人在不同地點的行程、兩件都需要專注的事（上課、開會、考試、看醫生）。
        只輸出一個 JSON 物件，不要任何其他文字：{"canOverlap": true 或 false, "reason": "一句繁體中文理由"}
        """
        var user = "新行程：\(item.title)（\(range(item.start, item.end))"
        if let loc = item.location { user += "，地點：\(loc)" }
        user += "）\n衝突的既有行程：\n"
        user += conflicts.map { "- \($0.title)（\(range($0.start, $0.end))）" }.joined(separator: "\n")

        let text = try await sendRaw(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ], maxTokens: 200)

        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"),
              let data = String(text[a...b]).data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let can = obj["canOverlap"] as? Bool else {
            throw LLMError.decodeFailed(text)
        }
        return ConcurrencyVerdict(canOverlap: can, reason: obj["reason"] as? String ?? "")
    }

    private func sendOnce(to ep: AppConfig.Endpoint,
                          messages: [[String: Any]],
                          maxTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "model": ep.model,
            "temperature": 0,
            "max_tokens": maxTokens,
            // 關掉 Qwen 的思考模式，回應更快
            "chat_template_kwargs": ["enable_thinking": false],
            "messages": messages
        ]

        var req = URLRequest(url: ep.baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 90

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "unknown")
        }

        let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
        guard let content = completion.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.noContent
        }
        return content
    }

    // MARK: - Prompt

    static func systemPrompt(now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd (EEEE) HH:mm"
        let nowStr = f.string(from: now)

        // 未來 14 天的日期對照表：星期幾、明天、後天都直接查表，不讓模型自己推算
        var tpe = Calendar(identifier: .gregorian)
        tpe.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.timeZone = tpe.timeZone
        df.dateFormat = "yyyy-MM-dd EEEE"
        let today0 = tpe.startOfDay(for: now)
        // 注意：表裡不標「今天/明天/後天」。實測標了之後模型反而把「後天」算錯（46/60 vs 58/60）。
        let table = (0..<14).compactMap { i -> String? in
            guard let d = tpe.date(byAdding: .day, value: i, to: today0) else { return nil }
            return df.string(from: d)
        }.joined(separator: "\n        ")

        return """
        現在時間是 \(nowStr)，時區 Asia/Taipei。
        接下來 14 天的日期對照（星期幾請直接查這張表，只會是今天或之後）：
        \(table)
        你的任務：把使用者輸入的每個活動抽成 JSON 陣列。每個元素欄位：
        - type: "event"（有明確時間點的行程）或 "todo"（只有截止日或沒有時間的待辦）
        - title: 簡短標題（字串）
        - start: 開始時間，ISO8601 含時區，例如 2026-10-02T15:00:00+08:00；不確定則用 null
        - end: 結束時間，同格式；沒有就用 null
        - location: 地點字串；沒有就用 null
        - allDay: 布林，整天行程為 true

        規則：
        - 相對日期（下週三、後天、月底）以上面的現在時間換算成實際日期。
        - 時間一律以使用者寫的為準。使用者寫了數字就照用，絕對不要依活動類型（早餐、午餐、晚餐、開會…）自己猜時間：
          「10」「10.」「10點」「10時」「10:00」都是十點整；「10點半」是十點三十分；「10點15」是十點十五分。
        - 使用者沒寫上午或下午時，只用來判斷「上午還是下午」，不能改掉使用者寫的小時數：
          早上、早晨、早餐 → 上午；下午 → 12 點以後的同一個數字（3 點 → 15:00）；
          晚上、晚餐、夜 → 晚上（7 點 → 19:00）；都沒有線索就挑最近的未來時間。
        - 只寫星期幾（例如「週五」）：用上面日期對照表裡最近的那一天；「下週五」是下一週的週五。
        - 使用者只寫了日期、完全沒寫時間（例如「明天吃早餐」）：type 用 "todo"、allDay 用 true、
          start 用當天 T00:00:00 加時區。不要編造時間，也不要把它當成午夜的行程。
        - 沒有指定結束時間的行程，end 用 null（app 會自動補一小時）。
        - 只輸出 JSON 陣列本身，不要有任何解釋文字、不要包 markdown code block。
        """
    }

    // MARK: - Decoding

    /// 從模型輸出裡撈出 JSON 陣列（容忍前後多餘文字或 ```json 包裹）。
    static func decodeItems(from content: String) throws -> [ParsedItem] {
        let cleaned = stripToJSONArray(content)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodeFailed(content)
        }
        do {
            return try JSONDecoder().decode([ParsedItem].self, from: data)
        } catch {
            throw LLMError.decodeFailed("\(error)\n原文：\(content)")
        }
    }

    private static func stripToJSONArray(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: "```") {
            // 去掉 ```json ... ``` 包裹
            t = String(t[r.upperBound...])
            if t.hasPrefix("json") { t.removeFirst(4) }
            if let end = t.range(of: "```") { t = String(t[..<end.lowerBound]) }
        }
        // 只保留第一個 [ 到最後一個 ]
        if let a = t.firstIndex(of: "["), let b = t.lastIndex(of: "]") {
            t = String(t[a...b])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI 回應結構

    private struct ChatCompletion: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }
}
