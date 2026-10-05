import Foundation

/// 一句話上網找活動：搜尋在記吧的伺服器上做（Brave 金鑰只放在伺服器），
/// 伺服器回傳搜尋摘要與前幾個網頁的文字，再交給模型抽出行程 / 待辦。
struct WebSearchService {

    enum SearchError: LocalizedError {
        case noKey
        case requestFailed(String)
        case noResults
        var errorDescription: String? {
            switch self {
            case .noKey: return "尚未設定邀請金鑰（請到設定填入）"
            case .requestFailed(let s): return s
            case .noResults: return "網路上找不到相關結果"
            }
        }
    }

    private struct Response: Decodable {
        struct Item: Decodable { let title: String; let url: String; let description: String? }
        struct Page: Decodable { let url: String; let text: String }
        let results: [Item]?
        let pages: [Page]?
        let error: String?
    }

    private let llm = LLMClient()

    /// 以自然語言查詢網路，回傳可排入的 ParsedItem。
    func search(query: String, now: Date = Date()) async throws -> [ParsedItem] {
        guard let key = AppConfig.gatewayKey else { throw SearchError.noKey }
        var req = URLRequest(url: AppConfig.gatewayURL.appendingPathComponent("search"))
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw SearchError.requestFailed(decoded?.error ?? (code == 401 ? "邀請金鑰無效" : "搜尋失敗（\(code)）"))
        }
        let results = decoded?.results ?? []
        guard !results.isEmpty else { throw SearchError.noResults }

        let snippetBlock = results.prefix(6).map {
            "・\($0.title)\n  \($0.description ?? "")\n  \($0.url)"
        }.joined(separator: "\n")
        let pageBlock = (decoded?.pages ?? []).map { "【來源：\($0.url)】\n" + String($0.text.prefix(4000)) }
            .joined(separator: "\n\n")
        return try await llm.extractFromWeb(query: query, snippets: snippetBlock, pages: pageBlock, now: now)
    }

    /// 抓網頁並粗略轉成純文字（去標籤、去 script/style）。
    static func fetchPageText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { return "" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (iPhone) AutoCal", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { return "" }
        return Self.htmlToText(html)
    }

    static func htmlToText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "head"] {
            s = s.replacingOccurrences(
                of: "<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
             .replacingOccurrences(of: "&amp;", with: "&")
             .replacingOccurrences(of: "&lt;", with: "<")
             .replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(\\s*\\n\\s*){2,}", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
