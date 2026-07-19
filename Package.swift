// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AIVoiceInput",
    platforms: [
        // .v13 = MenuBarExtra 下限;.v15 = 本机 SDK 15.5 符号上限;.v26 编译失败(PLAN §5.2)
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AIVoiceInput",
            path: "Sources/AIVoiceInput"
        )
    ]
)
