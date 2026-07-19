import Foundation

/// 去口头禅本地正则后处理(M5 第二层;prompt 是第一层)。
/// **保守**:激进清洗会误删真实内容(FINDINGS 实测:「记得先跑一下test」被 prompt 删成
/// 「就是先跑一下test」)——所以只删「独立成词/词组」的口头禅,绝不删子串
/// (unlike 里的 like、类似 里的「似」都不动)。默认关闭,由 Advanced 开关控制。
public enum TextPostProcessor {
    /// 中文口头禅:作为独立片段出现时才删(前后是标点/空白/串首尾)
    private static let chineseFillers = ["嗯", "呃", "唉", "那个", "这个", "就是说", "然后呢"]
    /// 英文口头禅:词边界匹配(\b),大小写不敏感
    private static let englishFillers = ["um", "uh", "erm", "you know", "i mean", "kind of", "sort of"]

    public static func removeFillers(_ text: String) -> String {
        var result = text

        // 英文:\b 词边界,避免 unlike/liked 误伤
        for filler in englishFillers {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b[,，]?\\s?"
            result = replace(pattern, in: result, options: [.caseInsensitive])
        }

        // 中文:前边界=串首/空白/标点,后边界=可选逗号 + 空白/标点/串尾
        for filler in chineseFillers {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            let pattern = "(^|(?<=[\\s，,。！？、]))\(escaped)[，,]?(?=[\\s，,。！？、]|$)"
            result = replace(pattern, in: result, options: [])
        }

        return cleanupWhitespace(result)
    }

    private static func replace(_ pattern: String, in text: String, options: NSRegularExpression.Options) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// 清理清洗后残留:多空格→单空格、标点前空格、串首尾空白
    private static func cleanupWhitespace(_ text: String) -> String {
        var result = text
        result = replace("[ \\t]{2,}", in: result, options: [])   // 折叠多空格
        result = replace(" +([,，.。!!?？])", in: result, options: []) // 标点前空格
        result = replace("^[\\s,，、]+", in: result, options: [])   // 串首残留标点/空白
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
