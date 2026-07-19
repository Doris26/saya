import os

/// os.Logger 封装。查看:`/usr/bin/log stream --predicate 'subsystem == "com.yujunzou.ai-voice-input"' --level info`
/// (zsh 内置 log 会挡住 /usr/bin/log;.info 不落盘,自动化验证用 log stream 而非 log show)
///
/// 隐私政策(grill #27):transcript 正文、API Key、Authorization 头一律不得 .public;
/// request/response body 任何级别不落日志。
public enum Log {
    private static let subsystem = "com.yujunzou.ai-voice-input"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let audio = Logger(subsystem: subsystem, category: "audio")      // M1
    public static let transcribe = Logger(subsystem: subsystem, category: "transcribe") // M2
    public static let inject = Logger(subsystem: subsystem, category: "inject")    // M3
}
