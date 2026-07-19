import Testing

@testable import AIVoiceInputCore

@Suite struct TextPostProcessorTests {
    @Test func removesStandaloneChineseFillers() {
        #expect(TextPostProcessor.removeFillers("嗯,我们先跑一下测试。") == "我们先跑一下测试。")
        #expect(TextPostProcessor.removeFillers("那个,帮我 merge 一下。") == "帮我 merge 一下。")
    }

    @Test func removesStandaloneEnglishFillers() {
        #expect(TextPostProcessor.removeFillers("um, let's ship it.") == "let's ship it.")
        #expect(TextPostProcessor.removeFillers("I mean, it works.") == "it works.")
    }

    @Test func doesNotTouchSubstrings() {
        // 关键保守性:unlike 里的 like、umbrella 里的 um 不能被删
        #expect(TextPostProcessor.removeFillers("This is unlike umbrella.") == "This is unlike umbrella.")
        // 中文子串:「这个」是口头禅,但「这个人」里的应否删?独立成词才删——「这个人」中「这个」后是「人」非边界,保留
        #expect(TextPostProcessor.removeFillers("这个人很好。") == "这个人很好。")
    }

    @Test func preservesRealContentFromFindings() {
        // FINDINGS 反例:激进 prompt 曾把「记得先跑一下test」删成「就是先跑一下test」
        // 本地正则不该动这句实义内容
        let input = "记得先跑一下 test 再 commit。"
        #expect(TextPostProcessor.removeFillers(input) == input)
    }

    @Test func emptyAndCleanInputUnchanged() {
        #expect(TextPostProcessor.removeFillers("") == "")
        #expect(TextPostProcessor.removeFillers("干净的一句话。") == "干净的一句话。")
    }
}
