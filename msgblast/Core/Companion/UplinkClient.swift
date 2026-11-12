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

// MARK: - Phase 3 sends (GET /imsg/sends, POST /imsg/send-results)

public enum SendsError: Error, Equatable {
    case notHTTPS, unauthorized
    /// 409 on a result: HomeChat already holds a different result for this send.
    case conflict
    /// 404 on a result: HomeChat doesn't know this send.
    case unknownSend
    case rejected(Int)
    /// 429 and 5xx carry the status; transport errors carry nil.
    case retryable(Int?)
    case badResponse
}

public protocol CompanionSendUplinking: Sendable {
    func fetchSends(wait: Int) async throws(SendsError) -> [ApprovedSend]
    func postResult(_ result: SendResult) async throws(SendsError)
}

extension UplinkClient: CompanionSendUplinking {
    public static let maxSendsPerPage = 5

    public func fetchSends(wait: Int) async throws(SendsError) -> [ApprovedSend] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("imsg/sends"),
                                             resolvingAgainstBaseURL: false) else { throw .notHTTPS }
        components.queryItems = [URLQueryItem(name: "wait", value: String(wait))]
        guard let url = components.url else { throw .notHTTPS }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(wait + 15)
        let (data, status) = try await perform(request)
        switch status {
        case 200..<300:
            guard let page = try? CompanionJSON.decoder.decode(SendsPage.self, from: data),
                  page.sends.count <= Self.maxSendsPerPage else { throw .badResponse }
            return page.sends
        default: throw Self.failure(status)
        }
    }

    public func postResult(_ result: SendResult) async throws(SendsError) {
        guard let body = try? CompanionJSON.encoder.encode(result) else { throw .badResponse }
        var request = URLRequest(url: baseURL.appendingPathComponent("imsg/send-results"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, status) = try await perform(request)
        switch status {
        case 200..<300: return
        case 404: throw .unknownSend
        case 409: throw .conflict
        default: throw Self.failure(status)
        }
    }

    private func perform(_ request: URLRequest) async throws(SendsError) -> (Data, Int) {
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else { throw .notHTTPS }
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .retryable(nil)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        return (data, http.statusCode)
    }

    private static func failure(_ status: Int) -> SendsError {
        switch status {
        case 401: .unauthorized
        case 429, 500..<600: .retryable(status)
        default: .rejected(status)
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
