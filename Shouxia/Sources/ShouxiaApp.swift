import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .showShouxiaWindow, object: nil) }
        return true
    }
}
extension Notification.Name { static let showShouxiaWindow = Notification.Name("showShouxiaWindow") }

@main
struct ShouxiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = DownloadStore()
    // A dedicated monochrome glyph keeps the mascot legible at menu-bar scale.
    private static let menuBarMascot: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 9.1, y: 19))
            outline.curve(to: NSPoint(x: 12.9, y: 19), controlPoint1: NSPoint(x: 10, y: 20.5), controlPoint2: NSPoint(x: 12, y: 20.5))
            outline.line(to: NSPoint(x: 19.3, y: 6.5))
            outline.curve(to: NSPoint(x: 17.2, y: 3.4), controlPoint1: NSPoint(x: 20.3, y: 4.5), controlPoint2: NSPoint(x: 19.1, y: 3.4))
            outline.line(to: NSPoint(x: 4.8, y: 3.4))
            outline.curve(to: NSPoint(x: 2.7, y: 6.5), controlPoint1: NSPoint(x: 2.9, y: 3.4), controlPoint2: NSPoint(x: 1.7, y: 4.5))
            outline.close()
            outline.lineWidth = 1.7
            outline.lineJoinStyle = .round
            outline.stroke()
            for x in [8.5, 12.1] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 12.6, width: 1.5, height: 1.8)).fill()
            }
            let wrap = NSBezierPath()
            wrap.move(to: NSPoint(x: 4.5, y: 8.9))
            wrap.line(to: NSPoint(x: 7.9, y: 7.5))
            wrap.move(to: NSPoint(x: 14.2, y: 7.5))
            wrap.line(to: NSPoint(x: 17.6, y: 9.2))
            wrap.lineWidth = 1.5
            wrap.lineCapStyle = .round
            wrap.stroke()
            let play = NSBezierPath()
            play.move(to: NSPoint(x: 9.5, y: 10.3))
            play.line(to: NSPoint(x: 13.4, y: 8))
            play.line(to: NSPoint(x: 9.5, y: 5.7))
            play.close(); play.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
    init() { TypeStyle.register() }
    var body: some Scene {
        Window("Video Extractor", id: "main") {
            MainView(store: store)
                .preferredColorScheme(.dark)
                .task { store.start() }
        }
        .defaultSize(width: 900, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("截取本地视频…") { ClipWindow.shared.choose() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("快捷输入") { QuickWindow.shared.show(store: store) }
                Button("打开下载文件夹") { FileActions.revealFolder(store.destinationPath) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("刷新下载任务") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button("快速上手") { NotificationCenter.default.post(name:.showShouxiaWindow,object:nil); store.showQuickStart=true }
                Button("使用说明") { FileActions.showHelp() }
                Button("打开后台日志") { FileActions.openLog() }
            }
        }
        MenuBarExtra {
            QuickPanel(store: store)
                .preferredColorScheme(.dark)
        } label: {
            Image(nsImage: Self.menuBarMascot)
                .renderingMode(.template)
                .accessibilityLabel("Video Extractor")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor enum FileActions {
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/MeTube", isDirectory: true) }
    static func revealFolder(_ path: String? = nil) { NSWorkspace.shared.open(path.map { URL(fileURLWithPath:$0) } ?? root) }
    @discardableResult static func chooseFolder(store: DownloadStore) -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择视频保存文件夹"; panel.prompt = "选择文件夹"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath:store.destinationPath,isDirectory:true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        store.setDestination(url)
        return true
    }
    static func reveal(_ item: DownloadItem) {
        if let url = item.localFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    static func open(_ item: DownloadItem) {
        if let url = item.localFileURL { NSWorkspace.shared.open(url) }
    }
    static func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Shouxia/backend.log")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
    static func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Video Extractor · 本地影音下载"
        alert.informativeText = "先粘贴公开视频链接或分享文字，选择视频/音频、画质与保存位置后提取。新用户可从帮助菜单打开“快速上手”。MP4 源格式仅选择源站提供的格式，不进行转码。\n\n本版本使用已配置的本机 Colima（metube 配置）、Docker（colima-metube 上下文）与 MeTube（metube 容器），不会自动安装。可在设置中检查后台依赖。\n\n先直接下载。网站访问辅助属于可选尝试，可在快速上手中展开说明；它默认关闭，解析失败本身不能证明需要登录。手动文件、代理和请求头位于高级设置。\n\n提交结果未确认时，先停止并核对。保存失败时选择可写文件夹，再重试保存；已提交任务保留原位置，重试保存使用当前文件夹。\n\n保存完成后可打开文件、在 Finder 中显示或截取片段。剪辑默认原视频尺寸，也可选择常用尺寸，等比完整显示并填黑；导出新文件保留源视频。关闭窗口后仍可从菜单栏操作，退出应用不会中断已提交的后台下载。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
