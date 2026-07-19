import Testing

@testable import AIVoiceInputCore

@Suite struct L10nTests {
    /// 覆盖率:每个 key 的 zh + en 都非空(穷举 switch 已保证无缺失 key,这里保证无空串)
    @Test func everyKeyHasNonEmptyBothLanguages() {
        for key in LocKey.allCases {
            let (zh, en) = L10n.pair(key)
            #expect(!zh.isEmpty, "zh 缺失: \(key)")
            #expect(!en.isEmpty, "en 缺失: \(key)")
        }
    }

    /// zh 与 en 应当不同(除了刻意同形的少数,如 langZh/langEn 的 "中文"/"English" 品牌词、sk-… 占位)
    @Test func zhAndEnMostlyDiffer() {
        let allowedSame: Set<LocKey> = [.secAPIKey, .obKeyTitle, .apiKeyPlaceholderEmpty, .langZh, .langEn, .testHTTP]
        for key in LocKey.allCases where !allowedSame.contains(key) {
            let (zh, en) = L10n.pair(key)
            #expect(zh != en, "zh==en 未翻译?: \(key) = \(zh)")
        }
    }

    /// 非位置 printf 格式:zh/en 说明符个数必须一致(否则 String(format:) 会崩或错位)。
    /// 位置说明符(%1$ 等)天然安全,允许 zh/en 引用不同子集(如用量行 en 跳过 ¥ 只显 $)。
    @Test func nonPositionalFormatSpecifierCountsMatch() {
        func hasPositional(_ s: String) -> Bool { s.contains("$") }
        func specCount(_ s: String) -> Int {
            var count = 0
            let chars = Array(s)
            var i = 0
            while i < chars.count {
                if chars[i] == "%" {
                    if i + 1 < chars.count, chars[i + 1] == "%" { i += 2; continue }
                    count += 1
                }
                i += 1
            }
            return count
        }
        for key in LocKey.allCases {
            let (zh, en) = L10n.pair(key)
            if hasPositional(zh) || hasPositional(en) { continue } // 位置说明符,安全跳过
            #expect(specCount(zh) == specCount(en), "格式符个数不一致: \(key) zh=\(specCount(zh)) en=\(specCount(en))")
        }
    }

    @Test func languageResolution() {
        #expect(L10n(.zh).lang == .zh)
        #expect(L10n(.en).lang == .en)
        // system 跟随 preferredLanguages 首项
        #expect(L10n(.system, preferredLanguages: ["zh-Hans", "en"]).lang == .zh)
        #expect(L10n(.system, preferredLanguages: ["en-US", "zh"]).lang == .en)
        #expect(L10n(.system, preferredLanguages: ["fr-FR"]).lang == .en) // 非中文回落 en
        #expect(L10n(.system, preferredLanguages: []).lang == .en)
    }

    @Test func lookupReturnsCorrectLanguage() {
        #expect(L10n(.zh).t(.menuStart) == "开始录音")
        #expect(L10n(.en).t(.menuStart) == "Start recording")
    }

    @Test func formattedLookupWorks() {
        // 位置说明符:en 只取 minutes + usd(跳过 cny)
        let en = L10n(.en).t(.menuUsageMonth, 12.0, 0.5, 0.072)
        #expect(en.contains("12"))
        #expect(en.contains("0.072"))
        let zh = L10n(.zh).t(.menuUsageMonth, 12.0, 0.5, 0.072)
        #expect(zh.contains("¥0.50"))
        #expect(zh.contains("$0.072"))
    }
}
