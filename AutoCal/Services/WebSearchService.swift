import Foundation

/// 用 Brave 搜尋 API 在網路上找活動資訊，抓取前幾筆結果的內容，
/// 再交給 LLM 抽出行程 / 待辦。搜尋與抓取都在手機端進行。
struct WebSearchService {

    enum SearchError: LocalizedError {
        case noKey
        case requestFailed(String)
        case noResults
        var errorDescription: String? {
            switch self {
            case .noKey: return "尚未設定 Brave 搜尋金鑰（請到設定填入）"
            case .requestFailed(let s): return "搜尋失敗：\(s)"
            case .noResults: return "網路上找不到相關結果"
            }
        }
    }

    struct Result {
        let title: String
        let url: String
        let description: String
    }

    private let llm = LLMClient()

    /// 以自然語言查詢網路，回傳可排入的 ParsedItem。
    func search(query: String, now: Date = Date()) async throws -> [ParsedItem] {
        guard let key = AppConfig.braveAPIKey, !key.isEmpty else { throw SearchError.noKey }

        let results = try await braveSearch(query: query, key: key)
        guard !results.isEmpty else { throw SearchError.noResults }

        // 同時抓前兩筆結果的頁面內容，補充摘要（摘要常常沒有完整日期）。
        let topURLs = results.prefix(2).map(\.url)
        let pages: [String] = await withTaskGroup(of: String?.self) { group in
            for u in topURLs {
                group.addTask {
                    guard let text = try? await Self.fetchPageText(u), !text.isEmpty else { return nil }
                    return "【來源：\(u)】\n" + String(text.prefix(3500))
                }
            }
            var out: [String] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }

        let snippetBlock = results.prefix(5).map {
            "・\($0.title)\n  \($0.description)\n  \($0.url)"
        }.joined(separator: "\n")
        let pageBlock = pages.joined(separator: "\n\n")

        return try await llm.extractFromWeb(query: query,
                                            snippets: snippetBlock,
                                            pages: pageBlock,
                                            now: now)
    }

    // MARK: - Brave API

    private func braveSearch(query: String, key: String) async throws -> [Result] {
        var comp = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        comp.queryItems = [
            .init(name: "q", value: query),
            .init(name: "count", value: "5"),
            .init(name: "country", value: "tw"),
            .init(name: "search_lang", value: "zh-hant")
        ]
        var req = URLRequest(url: comp.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SearchError.requestFailed("無回應")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw SearchError.requestFailed("HTTP \(http.statusCode) \(msg.prefix(200))")
        }

        let decoded = try JSONDecoder().decode(BraveResponse.self, from: data)
        return (decoded.web?.results ?? []).map {
            Result(title: $0.title, url: $0.url, description: $0.description ?? "")
        }
    }

    /// 抓網頁並粗略轉成純文字（去標籤、去 script/style）。
    private static func fetchPageText(_ urlString: String) async throws -> String {
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

    // MARK: - Brave 回應結構

    private struct BraveResponse: Decodable {
        struct Web: Decodable { let results: [Item]? }
        struct Item: Decodable { let title: String; let url: String; let description: String? }
        let web: Web?
    }
}
