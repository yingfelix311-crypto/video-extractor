import AppKit
import Foundation

final class PickerDelegate: NSObject, NSApplicationDelegate {
func applicationDidFinishLaunching(_ notification: Notification) {
NSApp.activate(ignoringOtherApps: true)
let panel = NSOpenPanel()
panel.title = "选择视频保存文件夹"
panel.message = "为 Video Extractor 选择保存位置（当前为交互预览）。"
panel.prompt = "选择文件夹"
panel.canChooseFiles = false
panel.canChooseDirectories = true
panel.allowsMultipleSelection = false
panel.canCreateDirectories = true
if CommandLine.arguments.count > 1 {
    panel.directoryURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
}
let selected = panel.runModal() == .OK ? panel.url?.path : nil
let payload: [String: Any] = selected.map { ["path": $0] } ?? ["cancelled": true]
let data = try! JSONSerialization.data(withJSONObject: payload)
print(String(decoding: data, as: UTF8.self))
NSApp.terminate(nil)
}
}
let app = NSApplication.shared
let delegate = PickerDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
