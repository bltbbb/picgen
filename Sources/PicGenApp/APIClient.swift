import Foundation
import UIKit

struct GenResult {
    let image: UIImage
    let imageURL: URL?
    let ms: Int
    let content: String
}

/// 上游给的图片可能是远程链接，也可能是内联的 data:image/...;base64
enum ImageSource {
    case remote(URL)
    case data(Data)
}

enum GenError: LocalizedError {
    case emptyPrompt
    case badBase(String)
    case http(Int, String)
    case noImage(String)
    case badResponse(String)
    case imageDownload(Int)
    case badImageData
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "提示词为空"
        case .badBase(let s):
            return "接口地址不对：\(s)"
        case .http(let code, let msg):
            return "HTTP \(code)：\(msg)"
        case .noImage(let preview):
            return "响应里没有图片链接：\(preview)"
        case .badResponse(let msg):
            return "响应解析失败：\(msg)"
        case .imageDownload(let code):
            return "图片下载失败（HTTP \(code)）"
        case .badImageData:
            return "图片数据解析失败（上游给的格式不支持）"
        case .network(let msg):
            return "网络错误：\(msg)"
        }
    }
}

/// AxonHub 中继（grok-imagine）客户端。
/// 注意：该站标准 `/v1/images/generations` 不可用（400 messages are required），
/// 生图必须走 `/v1/chat/completions`，从返回的 markdown `![image](url)` 里抠图片链接再下载。
struct APIClient {
    let base: String
    let apiKey: String
    let model: String
    let proxy: String

    func generate(prompt: String) async throws -> GenResult {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GenError.emptyPrompt }
        guard let url = Self.join(base, "chat/completions") else { throw GenError.badBase(base) }

        let start = Date()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 180
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": text]],
            "n": 1,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let session = Self.makeSession(proxy: proxy)
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: req)
        } catch {
            throw GenError.network(error.localizedDescription)
        }
        let data = result.0
        let response = result.1

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw GenError.http(code, Self.errorMessage(data: data))
        }

        let content = Self.content(from: data) ?? (String(data: data, encoding: .utf8) ?? "")
        guard let source = Self.imageSource(in: content) else {
            throw GenError.noImage(Self.preview(content))
        }

        let imageData: Data
        var remoteURL: URL?
        switch source {
        case .data(let bytes):
            imageData = bytes
        case .remote(let url):
            remoteURL = url
            let imageResult: (Data, URLResponse)
            do {
                imageResult = try await session.data(from: url)
            } catch {
                throw GenError.network(error.localizedDescription)
            }
            let imageCode = (imageResult.1 as? HTTPURLResponse)?.statusCode ?? 0
            guard imageCode == 200 else {
                throw GenError.imageDownload(imageCode)
            }
            imageData = imageResult.0
        }

        guard let image = UIImage(data: imageData) else {
            throw GenError.badImageData
        }

        return GenResult(
            image: image,
            imageURL: remoteURL,
            ms: Int(Date().timeIntervalSince(start) * 1000),
            content: content
        )
    }

    /// `GET /v1/models`，用于设置页的连通性测试
    func models() async throws -> [String] {
        guard let url = Self.join(base, "models") else { throw GenError.badBase(base) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let fetch: (Data, URLResponse)
        do {
            fetch = try await Self.makeSession(proxy: proxy).data(for: req)
        } catch {
            throw GenError.network(error.localizedDescription)
        }
        let data = fetch.0
        let response = fetch.1
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw GenError.http(code, Self.errorMessage(data: data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else {
            throw GenError.badResponse("模型列表不是预期的 JSON")
        }
        return list.compactMap { $0["id"] as? String }
    }

    // MARK: - 工具

    /// base 可以是 `https://host` 或 `https://host/v1`，都能拼出 `.../v1/<path>`
    static func join(_ base: String, _ path: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return nil }
        let lower = b.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            b = "https://" + b
        }
        while b.hasSuffix("/") {
            b.removeLast()
        }
        if b.lowercased().hasSuffix("/v1") {
            return URL(string: b + "/" + path)
        }
        return URL(string: b + "/v1/" + path)
    }

    /// 代理留空 = 直连；填 `127.0.0.1:7890` 或 `http://127.0.0.1:7890` 走 HTTP 代理
    static func parseProxy(_ raw: String) -> (String, Int)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let r = s.range(of: "://") {
            s = String(s[r.upperBound...])
        }
        if let slash = s.firstIndex(of: "/") {
            s = String(s[s.startIndex..<slash])
        }
        let parts = s.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]), port > 0 else { return nil }
        return (String(parts[0]), port)
    }

    static func makeSession(proxy: String) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 180
        cfg.timeoutIntervalForResource = 300
        if let (host, port) = parseProxy(proxy) {
            cfg.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port,
            ]
        }
        return URLSession(configuration: cfg)
    }

    /// 从 chat 返回里取 `choices[0].message.content`
    static func content(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        if let s = message["content"] as? String { return s }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }

    /// 从响应文本里找图片：优先 markdown 图片，其次裸 data:image / 裸 http 链接。
    /// 上游既可能给 `![image](https://…)`，也可能给 `![image_1](data:image/png;base64,…)`。
    static func imageSource(in text: String) -> ImageSource? {
        let patterns = [
            "!\\[[^\\]]*\\]\\(\\s*([\\s\\S]*?)\\s*\\)",            // markdown 图片
            "(data:image/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=\\s]+)",  // 裸 data URL
            "(https?://[^\\s\"'<>)\\]]+)",                             // 裸 http 链接
        ]
        for pattern in patterns {
            guard let raw = firstMatch(in: text, pattern: pattern) else { continue }
            if let source = source(fromRaw: raw) { return source }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func source(fromRaw raw: String) -> ImageSource? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("data:image/") {
            guard let comma = trimmed.firstIndex(of: ",") else { return nil }
            let meta = trimmed[trimmed.startIndex..<comma].lowercased()
            let payload = String(trimmed[trimmed.index(after: comma)...])
            guard meta.contains(";base64") else { return nil }
            guard let bytes = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]) else { return nil }
            return .data(bytes)
        }
        var cleaned = trimmed
        while let last = cleaned.last, "。，、；：".contains(last) {
            cleaned.removeLast()
        }
        guard let url = URL(string: cleaned), let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        return .remote(url)
    }

    static func errorMessage(data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any] {
            let code = err["code"] as? String
            let message = err["message"] as? String
            let joined = [code, message].compactMap { $0 }.joined(separator: "：")
            if !joined.isEmpty { return joined }
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["message"] as? String {
            return message
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? "无响应内容" : preview(text)
    }

    static func preview(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 内联图片的 base64 会淹没错误信息，这里截掉
        if let range = s.range(of: "base64,") {
            s = String(s[s.startIndex..<range.lowerBound]) + "base64,<…>"
        }
        if s.count <= 200 { return s }
        return String(s.prefix(200)) + "…"
    }
}
