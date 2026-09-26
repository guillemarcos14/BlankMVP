// The runner prepends the actual production models, errors and HTTP client.
enum BlankSharedState { static let appInstallId = "fixture-install" }

enum AssistantAppSession {
    private static let lock = NSLock()
    private static var credentials = [String: String]()
    static func token(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return credentials[account]
    }
    static var userID: String? { token("access")?.components(separatedBy: "#").last }
    static func save(accessToken: String, refreshToken: String) {
        lock.lock(); defer { lock.unlock() }
        credentials = ["access": accessToken, "refresh": refreshToken]
    }
    static func replace(accessToken: String, refreshToken: String, ifCurrent expected: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if credentials["access"] == expected {
            credentials = ["access": accessToken, "refresh": refreshToken]
        }
        return credentials["access"]
    }
}

private final class TransportStub: URLProtocol {
    struct Reply {
        var status = 200
        var body = "{}"
        var error: Error?
    }
    static var respond: (URLRequest) -> Reply = { _ in Reply() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.respond(request)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private let historyReply = #"{"ok":true,"turns":[],"next_before":null}"#
private let processingReply = #"{"ok":true,"turn":{"id":"turn-1","user_text":"hello","assistant_text":"","status":"processing","action_id":"","action_label":"","action_status":"","created_at":"2026-09-26T10:00:00Z"},"retry_after":3}"#

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct AssistantClientTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportStub.self]
        let session = URLSession(configuration: config)
        let client = AssistantAppClient(session: session, baseURL: URL(string: "https://blank.test/api")!,
            sessionRefresh: AssistantAppSessionRefresh())
        AssistantAppSession.save(accessToken: "expired#A", refreshToken: "refresh-A")

        // Overlapping history reads share one rotating refresh token.
        var refreshes = 0
        var appRequests = 0
        TransportStub.respond = { request in
            if request.url!.lastPathComponent == "app-auth" {
                refreshes += 1
                Thread.sleep(forTimeInterval: 0.05)
                return .init(body: #"{"ok":true,"access_token":"fresh#A","refresh_token":"rotated-A"}"#)
            }
            appRequests += 1
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired#A" {
                return .init(status: 401, body: #"{"error":"authentication_required"}"#)
            }
            return .init(body: historyReply)
        }
        async let first = client.history()
        async let second = client.history()
        let pages = try await [first, second]
        check(pages.count == 2 && refreshes == 1, "Concurrent 401s must refresh once")
        check(appRequests >= 3 && AssistantAppSession.token("refresh") == "rotated-A", "Refreshed credentials must persist")

        // An OTP login that finishes during refresh owns the session. The old
        // request must not run under that other user's identity or expose history.
        AssistantAppSession.save(accessToken: "expired#A", refreshToken: "refresh-A")
        appRequests = 0
        TransportStub.respond = { request in
            if request.url!.lastPathComponent == "app-auth" {
                AssistantAppSession.save(accessToken: "new-login#B", refreshToken: "refresh-B")
                return .init(body: #"{"ok":true,"access_token":"late-refresh#A","refresh_token":"rotated-A"}"#)
            }
            appRequests += 1
            return .init(status: 401, body: #"{"error":"authentication_required"}"#)
        }
        do { _ = try await client.history(); fatalError("Expected account-switch guard") }
        catch let error as AssistantAppError { check(error.code == "session_changed", "Wrong account-switch error") }
        check(appRequests == 1 && AssistantAppSession.token("access") == "new-login#B", "Late refresh overwrote a new login")

        // Transient refresh failure must remain retryable and clear single-flight.
        AssistantAppSession.save(accessToken: "expired#A", refreshToken: "refresh-A")
        refreshes = 0
        TransportStub.respond = { request in
            if request.url!.lastPathComponent == "app-auth" {
                refreshes += 1
                if refreshes == 1 { return .init(status: 502, body: #"{"error":"app_auth_unavailable"}"#) }
                return .init(body: #"{"ok":true,"access_token":"fresh#A","refresh_token":"rotated-A"}"#)
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer expired#A"
                ? .init(status: 401, body: #"{"error":"authentication_required"}"#)
                : .init(body: historyReply)
        }
        do { _ = try await client.history(); fatalError("Expected transient refresh failure") }
        catch let error as AssistantAppError {
            check(error.isRetryable && !error.requiresPhoneVerification, "A server outage must not force phone verification")
        }
        _ = try await client.history()
        check(refreshes == 2, "A failed refresh prevented later recovery")

        for (status, code, retryable, verify) in [
            (403, "installation_not_verified", false, true),
            (409, "conversation_in_progress", true, false),
            (409, "turn_payload_conflict", false, false),
            (429, "rate_limited", true, false),
            (503, "assistant_app_unavailable", true, false),
        ] {
            TransportStub.respond = { _ in .init(status: status, body: "{\"error\":\"\(code)\",\"detail\":\"SECRET INTERNAL TRACE\"}") }
            do { _ = try await client.history(); fatalError("Expected HTTP error \(status)") }
            catch let error as AssistantAppError {
                check(error.code == code && error.isRetryable == retryable && error.requiresPhoneVerification == verify, "Incorrect recovery for \(code)")
                check(!error.localizedDescription.contains("SECRET") && !error.localizedDescription.contains(code), "Raw backend error exposed")
            }
        }

        TransportStub.respond = { _ in .init(status: 202, body: processingReply) }
        let processing = try await client.send(text: "hello", turnId: "turn-1")
        check(processing.status == "processing" && !processing.canApply, "202 must preserve pending state, never imply applied")
        TransportStub.respond = { _ in .init(status: 404, body: #"{"error":"turn_not_found"}"#) }
        let missing = try await client.status(turnId: "turn-1")
        check(missing == nil, "Absent turn must permit recovery with the original ID")

        TransportStub.respond = { _ in .init(body: "not JSON") }
        do { _ = try await client.history(); fatalError("Expected malformed response error") }
        catch let error as AssistantAppError { check(error.code == "invalid_response" && error.isRetryable, "Malformed reply recovery") }
        for (urlCode, expected) in [(URLError.notConnectedToInternet, "network_unavailable"), (.timedOut, "request_timed_out")] {
            TransportStub.respond = { _ in .init(error: URLError(urlCode)) }
            do { _ = try await client.history(); fatalError("Expected network error") }
            catch let error as AssistantAppError { check(error.code == expected && error.isRetryable, "Network recovery") }
        }
        TransportStub.respond = { _ in .init(error: URLError(.cancelled)) }
        do { _ = try await client.history(); fatalError("Expected cancellation") }
        catch is CancellationError { }
        print("assistant client: refresh concurrency, identity switch, transient recovery, typed errors, 202/status, network and cancellation passed")
    }
}
