import Foundation
import Testing

@testable import AIVoiceInputCore

/// 同一 build 内 round-trip(SPIKE 6 实测 OSStatus=0)。跨 build ACL 弹窗(falsification ⑤,
/// grill #28)不在单测范围——那是 GUI 授权对话框,dev 期每重建一次 Allow。
@Suite(.serialized) struct KeychainHelperTests {
    private let service = "com.yujunzou.ai-voice-input.test"
    private let account = "unit-test-key"

    @Test func saveReadDeleteRoundTrip() throws {
        defer { KeychainHelper.delete(service: service, account: account) }
        try KeychainHelper.save("sk-DUMMY-round-trip-中文", service: service, account: account)
        #expect(KeychainHelper.read(service: service, account: account) == "sk-DUMMY-round-trip-中文")
        #expect(KeychainHelper.delete(service: service, account: account))
        #expect(KeychainHelper.read(service: service, account: account) == nil)
    }

    @Test func saveOverwrites() throws {
        defer { KeychainHelper.delete(service: service, account: account) }
        try KeychainHelper.save("first", service: service, account: account)
        try KeychainHelper.save("second", service: service, account: account)
        #expect(KeychainHelper.read(service: service, account: account) == "second")
    }

    @Test func readMissingReturnsNil() {
        KeychainHelper.delete(service: service, account: "never-saved")
        #expect(KeychainHelper.read(service: service, account: "never-saved") == nil)
    }
}
