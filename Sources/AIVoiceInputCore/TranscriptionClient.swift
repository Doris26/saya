import Foundation

public struct TranscriptionResult: Sendable {
    public let text: String
    /// usage 对象实测存在(FINDINGS §2-§3):可做成本核算
    public let totalTokens: Int?
}

/// OpenAI /v1/audio/transcriptions 客户端(multipart,async/await)。
/// 错误分类:401/429/网络/超时/过大/服务端(PLAN §1.2)。
public final class TranscriptionClient: Sendable {
    public enum TranscriptionError: LocalizedError, Equatable {
        case missingAPIKey
        case fileTooLarge(bytes: Int)
        case invalidKey
        case rateLimited
        case timeout
        case network(String)
        case server(status: Int, message: String)
        case emptyTranscript

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "未配置 OpenAI API Key(开发期:从环境变量 OPENAI_API_KEY 读)"
            case .fileTooLarge(let bytes):
                "录音文件过大(\(bytes / 1024 / 1024) MB > 25 MB 上限)"
            case .invalidKey:
                "API Key 无效(401)——请检查 Key"
            case .rateLimited:
                "请求过于频繁(429)——稍后重试"
            case .timeout:
                "转写超时(30s)——请检查网络"
            case .network(let detail):
                "网络错误:\(detail)"
            case .server(let status, let message):
                "服务端错误(\(status)):\(message)"
            case .emptyTranscript:
                "转写结果为空"
            }
        }
    }

    /// 25MB 超限是 mid-upload TLS abort 而非干净 413(实测,FINDINGS §2-§3)→ 必须本地预检
    public static let maxFileBytes = 25 * 1024 * 1024

    /// 默认 steering prompt:标点 + 强制简体(简繁非确定性实测 2/5 繁体,FINDINGS §2-§3)。
    /// prompt 按 input text_tokens 计费,保持短;激进去口头禅会误删内容 → 口头禅清洗留 M5 可选开关。
    public static let defaultPrompt = "请输出带标点的书面文本,中文使用简体中文输出。Punctuate properly."

    private let session: URLSession

    /// configuration 可注入(测试用 URLProtocol mock);默认 30s idle + 120s wall-clock 双 knob(grill #19)
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = min(configuration.timeoutIntervalForRequest, 30)
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    public func transcribe(
        fileURL: URL,
        apiKey: String,
        model: String = "gpt-4o-transcribe",
        prompt: String = TranscriptionClient.defaultPrompt,
        language: String? = nil // 中英混输留空最稳(实测 language=en 也压不住混输,FINDINGS)
    ) async throws -> TranscriptionResult {
        guard !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey }

        let audioData = try Data(contentsOf: fileURL)
        guard audioData.count <= Self.maxFileBytes else {
            throw TranscriptionError.fileTooLarge(bytes: audioData.count)
        }

        let request = buildRequest(
            audioData: audioData, filename: fileURL.lastPathComponent,
            apiKey: apiKey, model: model, prompt: prompt, language: language
        )

        // 30s 超时 + 1 次重试(仅幂等可重试错误:超时/网络/5xx;401/429 不重试)(PLAN §7#3)
        do {
            return try await send(request)
        } catch let error as TranscriptionError {
            switch error {
            case .timeout, .network, .server:
                Log.transcribe.info("retrying after: \(String(describing: error), privacy: .public)")
                return try await send(request)
            default:
                throw error
            }
        }
    }

    private func send(_ request: URLRequest) async throws -> TranscriptionResult {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut: throw TranscriptionError.timeout
            default: throw TranscriptionError.network(urlError.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.network("非 HTTP 响应")
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw TranscriptionError.invalidKey
        case 429:
            throw TranscriptionError.rateLimited
        default:
            throw TranscriptionError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        struct ResponseBody: Decodable {
            struct Usage: Decodable { let total_tokens: Int? }
            public let text: String
            let usage: Usage?
        }
        guard let body = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw TranscriptionError.server(status: 200, message: "响应解析失败")
        }
        let text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscript }
        return TranscriptionResult(text: text, totalTokens: body.usage?.total_tokens)
    }

    private func buildRequest(
        audioData: Data, filename: String, apiKey: String,
        model: String, prompt: String, language: String?
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "aivoiceinput-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        appendField("model", model)
        appendField("response_format", "json") // verbose_json/srt 实测 400(FINDINGS)
        appendField("prompt", prompt)
        if let language { appendField("language", language) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    private static func errorMessage(from data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        if let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = parsed.error?.message {
            return String(message.prefix(200))
        }
        return String(String(decoding: data, as: UTF8.self).prefix(200))
    }
}
