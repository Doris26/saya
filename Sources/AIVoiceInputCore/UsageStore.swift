import Foundation

/// 一次转写的用量记录。存本地 jsonl(~/Library/Application Support/Saya/usage.jsonl),不进 repo。
public struct UsageRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let audioSeconds: Double
    public let model: String
    public let costUSD: Double
    /// OpenAI response 的 usage.total_tokens(有就存,做透明化);成本仍按分钟价算(OpenAI 这俩模型按分钟计费)
    public let tokens: Int?
    /// true = 无真实音频时长、按其他方式估算(正常流程我们总有精确录音时长 → false)
    public let estimated: Bool

    public init(timestamp: Date, audioSeconds: Double, model: String, costUSD: Double, tokens: Int?, estimated: Bool) {
        self.timestamp = timestamp
        self.audioSeconds = audioSeconds
        self.model = model
        self.costUSD = costUSD
        self.tokens = tokens
        self.estimated = estimated
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let monthMinutes: Double
    public let monthCostUSD: Double
    public let todayMinutes: Double
    public let todayCostUSD: Double
    public let count: Int

    public static let empty = UsageSummary(monthMinutes: 0, monthCostUSD: 0, todayMinutes: 0, todayCostUSD: 0, count: 0)

    public var monthCostCNY: Double { monthCostUSD * UsageStore.usdToCny }
    public var todayCostCNY: Double { todayCostUSD * UsageStore.usdToCny }
}

/// 用量/花费追踪。append-only jsonl,聚合出本月/今日分钟数与花费。
public final class UsageStore: @unchecked Sendable {
    /// 分钟计价(OpenAI 官方口径,FINDINGS §3):gpt-4o-transcribe $0.006/min、mini $0.003/min
    public static let ratePerMinuteUSD: [String: Double] = [
        "gpt-4o-transcribe": 0.006,
        "gpt-4o-mini-transcribe": 0.003,
    ]
    /// 展示用近似汇率($→¥);仅用于 UI 展示,不影响记账(记账以 USD 为准)
    public static let usdToCny = 7.2

    /// 纯换算:音频时长 → 成本 USD(可单测)
    public static func costUSD(model: String, seconds: Double) -> Double {
        let rate = ratePerMinuteUSD[model] ?? ratePerMinuteUSD["gpt-4o-transcribe"]!
        return max(0, seconds) / 60.0 * rate
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.yujunzou.saya.usage")

    /// directory 可注入(测试用 temp dir),默认 ~/Library/Application Support/Saya/
    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saya", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("usage.jsonl")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    public func record(_ record: UsageRecord) {
        queue.sync {
            guard let line = try? Self.encoder.encode(record) else { return }
            var data = line
            data.append(0x0A) // '\n'
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    public func all() -> [UsageRecord] {
        queue.sync {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
            return content.split(separator: "\n").compactMap { line in
                try? Self.decoder.decode(UsageRecord.self, from: Data(line.utf8))
            }
        }
    }

    /// now/calendar 可注入(测试);默认取当前时间与本地日历
    public func summary(now: Date, calendar: Calendar = .current) -> UsageSummary {
        let records = all()
        let month = records.filter { calendar.isDate($0.timestamp, equalTo: now, toGranularity: .month) }
        let today = records.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        func minutes(_ rs: [UsageRecord]) -> Double { rs.reduce(0) { $0 + $1.audioSeconds } / 60.0 }
        func cost(_ rs: [UsageRecord]) -> Double { rs.reduce(0) { $0 + $1.costUSD } }
        return UsageSummary(
            monthMinutes: minutes(month), monthCostUSD: cost(month),
            todayMinutes: minutes(today), todayCostUSD: cost(today),
            count: records.count
        )
    }
}
