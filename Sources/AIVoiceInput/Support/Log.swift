import os

/// os.Logger 封装。查看:`log stream --predicate 'subsystem == "com.yujunzou.ai-voice-input"' --level info`
enum Log {
    private static let subsystem = "com.yujunzou.ai-voice-input"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")      // M1
    static let transcribe = Logger(subsystem: subsystem, category: "transcribe") // M2
    static let inject = Logger(subsystem: subsystem, category: "inject")    // M3
}
