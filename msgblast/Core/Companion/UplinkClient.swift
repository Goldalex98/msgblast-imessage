import Foundation

// iMessage companion (fork-only). POST /imsg/messages (docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md).
public enum UplinkError: Error, Equatable {
    case notHTTPS
    case unauthorized
    /// 413, 422, redirects and other 4xx: stop until something changes.
    case rejected(Int)
    /// 429 and 5xx carry the status; transport errors (offline, timeout) carry nil.
    case retryable(Int?)
    case badResponse
}

public struct UplinkClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .companionEphemeral) {
        self.baseURL = baseURL; self.token = token; self.session = session
    }

    public func post(_ batch: UplinkBatch) async throws(UplinkError) -> UplinkAck {
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else { throw .notHTTPS }
        guard let body = try? CompanionJSON.encoder.encode(batch) else { throw .badResponse }
        var request = URLRequest(url: baseURL.appendingPathComponent("imsg/messages"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .retryable(nil)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        switch http.statusCode {
        case 200..<300:
            guard let ack = try? CompanionJSON.decoder.decode(UplinkAck.self, from: data) else { throw .badResponse }
            return ack
        case 401: throw .unauthorized
        case 429, 500..<600: throw .retryable(http.statusCode)
        default: throw .rejected(http.statusCode)
        }
    }
}

extension URLSession {
    /// Ephemeral (no cookies, no cache), 30 s request timeout, and every redirect refused.
    public static let companionEphemeral: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: CompanionNoRedirects(), delegateQueue: nil)
    }()
}

private final class CompanionNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
