// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AIVoiceInput",
    platforms: [
        // .v13 = MenuBarExtra 下限;.v15 = 本机 SDK 15.5 符号上限;.v26 编译失败(PLAN §5.2)
        // test target 必须继承 .v14,否则 @Test 宏在默认 10.13 下破(PLAN §5.2-6)
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "AIVoiceInputCore",
            path: "Sources/AIVoiceInputCore"
        ),
        .executableTarget(
            name: "AIVoiceInput",
            dependencies: ["AIVoiceInputCore"],
            path: "Sources/AIVoiceInput"
        ),
        .testTarget(
            name: "AIVoiceInputCoreTests",
            dependencies: ["AIVoiceInputCore"],
            path: "Tests/AIVoiceInputCoreTests"
        ),
        // M3 两进程验收 harness(grill #13;dev/test 工具,不进 bundle.sh)
        .executableTarget(
            name: "InjectReceiver",
            path: "Tools/InjectReceiver"
        ),
        .executableTarget(
            name: "aivi-cli",
            dependencies: ["AIVoiceInputCore"],
            path: "Tools/aivi-cli"
        ),
    ]
)
