import Foundation
import Testing

@testable import AIVoiceInputCore

/// URLProtocol mock:拦截 TranscriptionClient 的请求,回放预设响应(测的是生产代码路径,
/// 只 mock I/O 边界——skill 214)。
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct TranscriptionClientTests {
    private func makeClient() -> TranscriptionClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return TranscriptionClient(configuration: config)
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02]).write(to: url)
        return url
    }

    private static func response(_ status: Int, _ body: String) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    @Test func classifies401AsInvalidKey() async throws {
        MockURLProtocol.handler = Self.response(401, #"{"error":{"message":"bad key"}}"#)
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TranscriptionClient.TranscriptionError.invalidKey) {
            _ = try await makeClient().transcribe(fileURL: url, apiKey: "sk-test")
        }
    }

    @Test func classifies429AsRateLimited() async throws {
        MockURLProtocol.handler = Self.response(429, #"{"error":{"message":"slow down"}}"#)
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TranscriptionClient.TranscriptionError.rateLimited) {
            _ = try await makeClient().transcribe(fileURL: url, apiKey: "sk-test")
        }
    }

    @Test func parsesSuccessWithUsage() async throws {
        MockURLProtocol.handler = Self.response(
            200, #"{"text":"帮我 review 一下这个 PR。","usage":{"total_tokens":42}}"#
        )
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await makeClient().transcribe(fileURL: url, apiKey: "sk-test")
        #expect(result.text == "帮我 review 一下这个 PR。")
        #expect(result.totalTokens == 42)
    }

    @Test func emptyTranscriptThrows() async throws {
        MockURLProtocol.handler = Self.response(200, #"{"text":"  "}"#)
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TranscriptionClient.TranscriptionError.emptyTranscript) {
            _ = try await makeClient().transcribe(fileURL: url, apiKey: "sk-test")
        }
    }

    @Test func missingKeyThrowsBeforeNetwork() async throws {
        MockURLProtocol.handler = nil // 不该碰网络
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TranscriptionClient.TranscriptionError.missingAPIKey) {
            _ = try await makeClient().transcribe(fileURL: url, apiKey: "")
        }
    }

    @Test func oversizeFileRejectedLocally() async throws {
        // 25MB 超限是 TLS abort 非干净 413(FINDINGS)→ 必须本地预检,不碰网络
        MockURLProtocol.handler = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("big-\(UUID().uuidString).m4a")
        let big = Data(count: TranscriptionClient.maxFileBytes + 1)
        try big.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TranscriptionClient.TranscriptionError.self) {
            _ = try await makeClient().transcribe(fileURL: url, apiKey: "sk-test")
        }
    }

    @Test func serverErrorRetriesOnceThenSurfaces() async throws {
        // 5xx 重试 1 次:计数器证明重试确实发生
        final class Counter: @unchecked Sendable {
            var count = 0
            let lock = NSLock()
            func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
        }
        let counter = Counter()
        MockURLProtocol.handler = { request in
            _ = counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"boom"}}"#.utf8))
        }
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TranscriptionClient.TranscriptionError.self) {
            _ = try await makeClient().transcribe(fileURL: url, apiKey: "sk-test")
        }
        #expect(counter.count == 2) // 1 次原始 + 1 次重试
    }

    @Test func defaultPromptForcesSimplifiedChinese() {
        // 简繁非确定性实测 2/5 繁体(FINDINGS)→ 强制简体 clause 必须在默认 prompt 里
        #expect(TranscriptionClient.defaultPrompt.contains("简体"))
    }
}
