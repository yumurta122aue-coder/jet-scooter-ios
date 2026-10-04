import Foundation

struct APIResponse {
    let status: Int
    let headers: [String: String]
    let body: String
    let elapsed: TimeInterval

    var isSuccess: Bool { (200..<300).contains(status) }

    var verdict: String {
        switch status {
        case 200, 201, 204: return "ok"
        case 400, 422:      return "the route exists — it wants a different body"
        case 401:           return "the route exists — your token is missing or expired"
        case 403:           return "the route exists — the token is not allowed here"
        case 404:           return "no such route"
        case 405:           return "the route exists — wrong HTTP method"
        case 429:           return "rate limited — slow down"
        case 500...599:     return "their server broke"
        default:            return "unexpected"
        }
    }
}

enum APIError: LocalizedError {
    case badURL(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s):     return "not a usable URL: \(s)"
        case .transport(let s):  return s
        }
    }
}

/// A thin, honest HTTP client. It knows the host and the auth scheme because
/// those were recovered from the vendor's own binary; it deliberately does not
/// guess route names, because a wrong guess tells you nothing and a right guess
/// still answers 401 without a token.
final class APIClient {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    func send(method: String,
              base: String,
              path: String,
              token: String?,
              body: String?) async throws -> APIResponse {

        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let cleanPath = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: cleanBase + cleanPath) else {
            throw APIError.badURL(cleanBase + cleanPath)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        if let token, !token.trimmingCharacters(in: .whitespaces).isEmpty {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            let value = trimmed.lowercased().hasPrefix("bearer ") ? trimmed : "Bearer \(trimmed)"
            request.setValue(value, forHTTPHeaderField: "Authorization")
        }

        if let body, !body.trimmingCharacters(in: .whitespaces).isEmpty,
           method.uppercased() != "GET", method.uppercased() != "HEAD" {
            request.httpBody = body.data(using: .utf8)
        }

        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(started)
            let http = response as? HTTPURLResponse

            var headers: [String: String] = [:]
            http?.allHeaderFields.forEach { key, value in
                headers["\(key)"] = "\(value)"
            }

            let text = String(data: data, encoding: .utf8)
                ?? "<\(data.count) bytes, not utf-8>"

            return APIResponse(status: http?.statusCode ?? 0,
                               headers: headers,
                               body: text,
                               elapsed: elapsed)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    /// Pretty-print JSON when it is JSON, otherwise hand back the raw text.
    static func pretty(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return text }
        return string
    }
}
