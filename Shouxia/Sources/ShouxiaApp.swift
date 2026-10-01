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
    var body: some Scene {
        Window("收下", id: "main") {
            MainView(store: store)
                .preferredColorScheme(.light)
                .task { store.start() }
        }
        .defaultSize(width: 810, height: 740)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开下载文件夹") { FileActions.revealFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("刷新下载任务") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button("使用说明") { FileActions.showHelp() }
                Button("打开后台日志") { FileActions.openLog() }
            }
        }
        MenuBarExtra {
            QuickPanel(store: store)
                .preferredColorScheme(.light)
        } label: {
            Image(systemName: "arrow.down.to.line")
                .accessibilityLabel("收下")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor enum FileActions {
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/MeTube", isDirectory: true) }
    static func revealFolder() { NSWorkspace.shared.open(root) }
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
        alert.messageText = "收下 · 本地影音下载"
        alert.informativeText = "粘贴或拖入一个视频链接，选择清晰度后点击收下。文件保存在 下载/MeTube。\n\n关闭窗口后，可从菜单栏再次打开。退出应用不会中断后台下载；如需释放后台内存，请使用桌面 MeTube视频下载 文件夹中的停止文件。\n\n第一版使用这台 Mac 已安装的 MeTube 环境。平台可能要求登录，不能保证所有链接均可下载。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
