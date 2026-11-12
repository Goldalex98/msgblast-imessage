import XCTest
@testable import msgblastCore

final class UplinkClientTests: XCTestCase {
    private let base = URL(string: "https://uplink-test.invalid")!

    override func tearDown() { UplinkStub.reset() }

    private func client(_ url: URL? = nil) -> UplinkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UplinkStub.self]
        return UplinkClient(baseURL: url ?? base, token: "test-token", session: URLSession(configuration: configuration))
    }

    private func batch() -> UplinkBatch {
        let message = CompanionMessage(guid: "00000000-0000-0000-0000-000000000001", rowid: 7, threadGUID: "iMessage;-;direct",
                                       fromMe: false, senderHandle: "+15550100001",
                                       sentAt: Date(timeIntervalSince1970: 1_794_000_000), kind: .text, text: "hi",
                                       replyToGUID: nil, attachmentCount: 0)
        return UplinkBatch(deviceID: "mac-0000aaaa", batchID: UUID(), cursor: 7, firstRun: false, threads: [],
                           messages: [message])
    }

    private func outcome(status: Int, body: String = "{}") async -> Result<UplinkAck, UplinkError> {
        UplinkStub.respond(status: status, body: body)
        do throws(UplinkError) { return .success(try await client().post(batch())) } catch { return .failure(error) }
    }

    func test_postsToImsgMessagesWithBearer() async throws {
        UplinkStub.respond(status: 200, body: #"{"accepted_cursor": 7}"#)
        let sent = batch()
        _ = try await client().post(sent)
        let request = try XCTUnwrap(UplinkStub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/imsg/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try CompanionJSON.decoder.decode(UplinkBatch.self, from: XCTUnwrap(request.httpBody)), sent)
    }

    func test_baseURLWithPathKeepsIt() async throws {
        UplinkStub.respond(status: 200, body: #"{"accepted_cursor": 7}"#)
        _ = try await client(URL(string: "https://uplink-test.invalid/hc")!).post(batch())
        XCTAssertEqual(UplinkStub.requests.first?.url?.path, "/hc/imsg/messages")
    }

    func test_200ReturnsAck() async {
        let result = await outcome(status: 200, body: #"{"accepted_cursor": 7}"#)
        XCTAssertEqual(try? result.get(), UplinkAck(acceptedCursor: 7))
    }

    func test_401IsUnauthorized() async {
        let result = await outcome(status: 401)
        XCTAssertEqual(result, .failure(.unauthorized))
    }

    func test_422IsRejected() async {
        let result413 = await outcome(status: 413)
        XCTAssertEqual(result413, .failure(.rejected(413)))
        let result422 = await outcome(status: 422)
        XCTAssertEqual(result422, .failure(.rejected(422)))
        let result302 = await outcome(status: 302)
        XCTAssertEqual(result302, .failure(.rejected(302)), "redirects are refused, never followed")
    }

    func test_503IsRetryable() async {
        let result503 = await outcome(status: 503)
        XCTAssertEqual(result503, .failure(.retryable(503)))
        let result429 = await outcome(status: 429)
        XCTAssertEqual(result429, .failure(.retryable(429)))
    }

    func test_transportErrorIsRetryable() async {
        UplinkStub.fail(URLError(.notConnectedToInternet))
        do throws(UplinkError) {
            _ = try await client().post(batch())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error, .retryable(nil))
        }
    }

    func test_garbage200IsBadResponse() async {
        let result = await outcome(status: 200, body: "<html>ok</html>")
        XCTAssertEqual(result, .failure(.badResponse))
    }

    func test_httpBaseURLRefused() async {
        UplinkStub.respond(status: 200, body: #"{"accepted_cursor": 7}"#)
        do throws(UplinkError) {
            _ = try await client(URL(string: "http://uplink-test.invalid")!).post(batch())
            XCTFail("expected notHTTPS")
        } catch {
            XCTAssertEqual(error, .notHTTPS)
        }
        XCTAssertTrue(UplinkStub.requests.isEmpty)
    }

    func test_sharedSessionRefusesRedirects() {
        XCTAssertEqual(URLSession.companionEphemeral.configuration.timeoutIntervalForRequest, 30)
        XCTAssertNotNil(URLSession.companionEphemeral.delegate)
        XCTAssertNil(URLSession.companionEphemeral.configuration.urlCache)
    }
}

final class UplinkStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var response: (status: Int, body: Data)?
    nonisolated(unsafe) private static var error: Error?

    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    static func respond(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        response = (status, Data(body.utf8)); error = nil
    }
    static func fail(_ failure: Error) { lock.lock(); defer { lock.unlock() }; error = failure; response = nil }
    static func reset() { lock.lock(); defer { lock.unlock() }; captured = []; response = nil; error = nil }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "uplink-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var copy = request
        if copy.httpBody == nil, let stream = copy.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            copy.httpBody = body
        }
        Self.lock.lock()
        Self.captured.append(copy)
        let response = Self.response, error = Self.error
        Self.lock.unlock()
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let (status, body) = response ?? (500, Data())
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Phase 3 sends

extension UplinkClientTests {
    private func sendsOutcome(status: Int, body: String = "{}") async -> Result<[ApprovedSend], SendsError> {
        UplinkStub.respond(status: status, body: body)
        do throws(SendsError) { return .success(try await client().fetchSends(wait: 25)) } catch { return .failure(error) }
    }

    private func resultOutcome(status: Int) async -> Result<Void, SendsError> {
        UplinkStub.respond(status: status, body: "{}")
        let result = SendResult(sendID: "snd-1", outcome: .sent, anchorGUID: "g", textSHA256: "h", detail: .confirmed)
        do throws(SendsError) { try await client().postResult(result); return .success(()) } catch { return .failure(error) }
    }

    private func sendJSON(_ id: String) -> String {
        #"{"send_id": "\#(id)", "thread_guid": "iMessage;-;+15555550100", "participants_fingerprint": "fp", "text": "hi", "text_sha256": "h", "approved_at": "2026-11-12T14:00:00Z", "expires_at": "2026-11-12T14:10:00Z"}"#
    }

    func test_fetchSendsRequestShape() async throws {
        UplinkStub.respond(status: 200, body: #"{"sends": []}"#)
        _ = try await client().fetchSends(wait: 25)
        let request = try XCTUnwrap(UplinkStub.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/imsg/sends")
        XCTAssertEqual(request.url?.query, "wait=25")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.timeoutInterval, 40)
    }

    func test_fetchSendsEmptyAndPage() async throws {
        guard case .success(let none) = await sendsOutcome(status: 200, body: #"{"sends": []}"#) else { return XCTFail() }
        XCTAssertTrue(none.isEmpty)
        let page = #"{"sends": [\#(sendJSON("a")), \#(sendJSON("b"))]}"#
        guard case .success(let two) = await sendsOutcome(status: 200, body: page) else { return XCTFail() }
        XCTAssertEqual(two.map(\.sendID), ["a", "b"])
    }

    func test_fetchSendsMoreThanFiveIsBadResponse() async {
        let six = (1...6).map { sendJSON("s\($0)") }.joined(separator: ",")
        guard case .failure(let error) = await sendsOutcome(status: 200, body: #"{"sends": [\#(six)]}"#) else { return XCTFail() }
        XCTAssertEqual(error, .badResponse)
        guard case .failure(.badResponse) = await sendsOutcome(status: 200, body: "not json") else { return XCTFail() }
    }

    func test_postResultBody() async throws {
        UplinkStub.respond(status: 200, body: "{}")
        let result = SendResult(sendID: "snd-1", outcome: .ambiguous, anchorGUID: nil, textSHA256: "h", detail: .noReadback)
        try await client().postResult(result)
        let request = try XCTUnwrap(UplinkStub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/imsg/send-results")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(try CompanionJSON.decoder.decode(SendResult.self, from: XCTUnwrap(request.httpBody)), result)
    }

    func test_sendsStatusMapping() async {
        let fetchCases: [(Int, SendsError)] = [(401, .unauthorized), (404, .rejected(404)), (409, .rejected(409)),
                                               (429, .retryable(429)), (500, .retryable(500)), (302, .rejected(302))]
        for (status, expected) in fetchCases {
            guard case .failure(let error) = await sendsOutcome(status: status) else { XCTFail("\(status)"); continue }
            XCTAssertEqual(error, expected, "fetch \(status)")
        }
        let resultCases: [(Int, SendsError)] = [(401, .unauthorized), (404, .unknownSend), (409, .conflict),
                                                (429, .retryable(429)), (503, .retryable(503)), (302, .rejected(302)),
                                                (422, .rejected(422))]
        for (status, expected) in resultCases {
            guard case .failure(let error) = await resultOutcome(status: status) else { XCTFail("\(status)"); continue }
            XCTAssertEqual(error, expected, "result \(status)")
        }
        guard case .success = await resultOutcome(status: 200) else { return XCTFail() }
    }

    func test_sendsTransportErrorIsRetryable() async {
        UplinkStub.fail(URLError(.notConnectedToInternet))
        do throws(SendsError) { _ = try await client().fetchSends(wait: 25); XCTFail() } catch { XCTAssertEqual(error, .retryable(nil)) }
    }

    func test_sendsHTTPBaseRefused() async {
        let plain = client(URL(string: "http://uplink-test.invalid")!)
        do throws(SendsError) { _ = try await plain.fetchSends(wait: 25); XCTFail() } catch { XCTAssertEqual(error, .notHTTPS) }
        let result = SendResult(sendID: "s", outcome: .sent, anchorGUID: nil, textSHA256: "h", detail: .confirmed)
        do throws(SendsError) { try await plain.postResult(result); XCTFail() } catch { XCTAssertEqual(error, .notHTTPS) }
        XCTAssertTrue(UplinkStub.requests.isEmpty)
    }
}
