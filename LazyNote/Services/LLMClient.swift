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
        let messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt(now: now)],
            ["role": "user", "content": text]
        ]
        return try await send(messages: messages)
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

    // MARK: - 共用送出邏輯

    private func send(messages: [[String: Any]], maxTokens: Int = 800) async throws -> [ParsedItem] {
        let body: [String: Any] = [
            "model": AppConfig.model,
            "temperature": 0,
            "max_tokens": maxTokens,
            // 關掉 Qwen 的思考模式，回應更快
            "chat_template_kwargs": ["enable_thinking": false],
            "messages": messages
        ]

        var req = URLRequest(url: AppConfig.baseURL.appendingPathComponent("chat/completions"))
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
        return try Self.decodeItems(from: content)
    }

    // MARK: - Prompt

    static func systemPrompt(now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd (EEEE) HH:mm"
        let nowStr = f.string(from: now)

        return """
        現在時間是 \(nowStr)，時區 Asia/Taipei。
        你的任務：把使用者輸入的每個活動抽成 JSON 陣列。每個元素欄位：
        - type: "event"（有明確時間點的行程）或 "todo"（只有截止日或沒有時間的待辦）
        - title: 簡短標題（字串）
        - start: 開始時間，ISO8601 含時區，例如 2026-10-02T15:00:00+08:00；不確定則用 null
        - end: 結束時間，同格式；沒有就用 null
        - location: 地點字串；沒有就用 null
        - allDay: 布林，整天行程為 true

        規則：
        - 相對日期（下週三、後天、月底）以上面的現在時間換算成實際日期。
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
