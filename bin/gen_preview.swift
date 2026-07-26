// Saya UI preview generator — renders the actual menu-dropdown + recording HUD pill
// via SwiftUI ImageRenderer (headless, no window server). Not a desktop capture; a
// faithful render of the app's real UI styling. Output: docs/preview{,-zh}.png
//
// Run:  swiftc -O bin/gen_preview.swift -o /tmp/gen_preview && /tmp/gen_preview
import SwiftUI
import AppKit

struct Row: Identifiable { let id = UUID(); let text: String; let kind: Kind
    enum Kind { case status, dim, item, divider } }

func menuRows(_ zh: Bool) -> [Row] {
    let sample = "帮我 review this PR then merge 到 main。"
    if zh {
        return [
            Row(text: "录音中… 0:03 · -17 dB", kind: .status),
            Row(text: "触发 🌐 fn 单键 · 已触发 12 次", kind: .dim),
            Row(text: "", kind: .divider),
            Row(text: "停止录音", kind: .item),
            Row(text: "取消录音(Esc)", kind: .item),
            Row(text: "", kind: .divider),
            Row(text: "最近转写:\(sample)", kind: .dim),
            Row(text: "复制上次转写", kind: .item),
            Row(text: "", kind: .divider),
            Row(text: "本月 42 分钟 · ¥1.81($0.252)", kind: .dim),
            Row(text: "今日 6 分钟 · ¥0.26", kind: .dim),
            Row(text: "", kind: .divider),
            Row(text: "设置…", kind: .item),
            Row(text: "退出 Saya", kind: .item),
        ]
    }
    return [
        Row(text: "Recording… 0:03 · -17 dB", kind: .status),
        Row(text: "Trigger 🌐 fn key · fired 12×", kind: .dim),
        Row(text: "", kind: .divider),
        Row(text: "Stop recording", kind: .item),
        Row(text: "Cancel (Esc)", kind: .item),
        Row(text: "", kind: .divider),
        Row(text: "Last: \(sample)", kind: .dim),
        Row(text: "Copy last transcript", kind: .item),
        Row(text: "", kind: .divider),
        Row(text: "This month: 42 min · $0.252", kind: .dim),
        Row(text: "Today: 6 min · $0.036", kind: .dim),
        Row(text: "", kind: .divider),
        Row(text: "Settings…", kind: .item),
        Row(text: "Quit Saya", kind: .item),
    ]
}

struct WaveBars: View {
    // representative static waveform
    let heights: [CGFloat] = [0.2,0.35,0.5,0.75,0.55,0.9,0.65,0.4,0.7,0.85,0.5,0.6,0.35,0.25,0.45,0.3]
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 2.5, height: max(3, heights[i] * 18))
            }
        }.frame(height: 18)
    }
}

struct HUDPill: View {
    let zh: Bool
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(.red).frame(width: 9, height: 9)
            Text(zh ? "正在听…" : "Listening…").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            WaveBars().frame(width: 60)
            Text("0:03").font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(white: 0.14).opacity(0.96), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}

struct MenuCard: View {
    let zh: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(menuRows(zh)) { row in
                switch row.kind {
                case .divider:
                    Divider().overlay(Color.white.opacity(0.10)).padding(.vertical, 4)
                case .status:
                    Text(row.text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                case .dim:
                    Text(row.text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                case .item:
                    Text(row.text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12).padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 320, alignment: .leading)
        .background(Color(white: 0.12).opacity(0.98), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }
}

struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Text("🎙️").font(.system(size: 13))
            Image(systemName: "wifi").font(.system(size: 12))
            Image(systemName: "battery.75").font(.system(size: 12))
            Text("Mon 9:41").font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18).frame(height: 26)
        .background(Color.black.opacity(0.25))
    }
}

struct Preview: View {
    let zh: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20),
                                    Color(red: 0.18, green: 0.14, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                MenuBarStrip()
                HStack {
                    Spacer()
                    MenuCard(zh: zh).padding(.top, 8).padding(.trailing, 40)
                }
                Spacer()
                HUDPill(zh: zh).padding(.bottom, 30)
            }
            VStack {
                Spacer()
                Text(zh ? "按 fn 说话 · 中英文混说 · 文字直接落到光标处"
                        : "Press fn, speak — 中/EN mixed — text lands at your cursor")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 84)
            }
        }
        .frame(width: 860, height: 540)
    }
}

@MainActor func render(zh: Bool, to path: String) {
    let renderer = ImageRenderer(content: Preview(zh: zh))
    renderer.scale = 2
    guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("RENDER FAILED \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(png.count) bytes, \(img.size))")
}

let root = FileManager.default.currentDirectoryPath
MainActor.assumeIsolated {
    render(zh: false, to: "\(root)/docs/preview.png")
    render(zh: true, to: "\(root)/docs/preview-zh.png")
}
