import Foundation
import Testing

@testable import AIVoiceInputCore

@Suite struct UsageCostTests {
    @Test func perMinuteCostConversion() {
        // gpt-4o-transcribe $0.006/min
        #expect(abs(UsageStore.costUSD(model: "gpt-4o-transcribe", seconds: 60) - 0.006) < 1e-9)
        #expect(abs(UsageStore.costUSD(model: "gpt-4o-transcribe", seconds: 30) - 0.003) < 1e-9)
        // mini $0.003/min
        #expect(abs(UsageStore.costUSD(model: "gpt-4o-mini-transcribe", seconds: 60) - 0.003) < 1e-9)
        // 未知模型回落 transcribe 价
        #expect(abs(UsageStore.costUSD(model: "unknown", seconds: 60) - 0.006) < 1e-9)
        // 负时长截断为 0
        #expect(UsageStore.costUSD(model: "gpt-4o-transcribe", seconds: -5) == 0)
    }
}

@Suite(.serialized) struct UsageStoreTests {
    private func tempStore() -> (UsageStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("saya-usage-test-\(UUID().uuidString)")
        return (UsageStore(directory: dir), dir)
    }

    @Test func recordAndReadRoundTrip() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rec = UsageRecord(timestamp: Date(), audioSeconds: 12, model: "gpt-4o-transcribe",
                              costUSD: 0.0012, tokens: 42, estimated: false)
        store.record(rec)
        let all = store.all()
        #expect(all.count == 1)
        #expect(all.first?.audioSeconds == 12)
        #expect(all.first?.tokens == 42)
    }

    @Test func appendsAcrossInstances() {
        let (store1, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store1.record(UsageRecord(timestamp: Date(), audioSeconds: 10, model: "m", costUSD: 0.001, tokens: nil, estimated: false))
        let store2 = UsageStore(directory: dir)
        store2.record(UsageRecord(timestamp: Date(), audioSeconds: 20, model: "m", costUSD: 0.002, tokens: nil, estimated: false))
        #expect(UsageStore(directory: dir).all().count == 2)
    }

    @Test func summaryBucketsMonthAndToday() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC

        // 今天两条:60s + 120s = 3 分钟
        store.record(UsageRecord(timestamp: now, audioSeconds: 60, model: "gpt-4o-transcribe", costUSD: 0.006, tokens: nil, estimated: false))
        store.record(UsageRecord(timestamp: now.addingTimeInterval(-3600), audioSeconds: 120, model: "gpt-4o-transcribe", costUSD: 0.012, tokens: nil, estimated: false))
        // 本月但非今天(9 天前):60s
        store.record(UsageRecord(timestamp: now.addingTimeInterval(-9 * 86400), audioSeconds: 60, model: "gpt-4o-transcribe", costUSD: 0.006, tokens: nil, estimated: false))
        // 上个月:不计入本月
        store.record(UsageRecord(timestamp: now.addingTimeInterval(-40 * 86400), audioSeconds: 600, model: "gpt-4o-transcribe", costUSD: 0.06, tokens: nil, estimated: false))

        let s = store.summary(now: now, calendar: cal)
        #expect(abs(s.todayMinutes - 3.0) < 1e-6)       // 60+120s
        #expect(abs(s.todayCostUSD - 0.018) < 1e-9)
        #expect(abs(s.monthMinutes - 4.0) < 1e-6)       // 今天 3 + 本月早些 1
        #expect(abs(s.monthCostUSD - 0.024) < 1e-9)
        #expect(s.count == 4)
    }

    @Test func cnyConversionApplied() {
        let s = UsageSummary(monthMinutes: 0, monthCostUSD: 1.0, todayMinutes: 0, todayCostUSD: 0.5, count: 0)
        #expect(abs(s.monthCostCNY - UsageStore.usdToCny) < 1e-9)
        #expect(abs(s.todayCostCNY - UsageStore.usdToCny * 0.5) < 1e-9)
    }
}
