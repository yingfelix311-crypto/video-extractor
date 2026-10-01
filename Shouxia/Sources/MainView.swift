import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var input = ""
    @AppStorage("downloadQuality") private var quality = "1080"
    @AppStorage("downloadAudioOnly") private var audioOnly = false
    @State private var dragOver = false
    @State private var filter = "全部"
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 22) {
                composer
                if let message = store.message { errorBanner(message) }
                library
            }.padding(.horizontal, 28).padding(.top, 24)
            footer
        }
        .foregroundStyle(Ink.dark).background(Ink.paper)
        .frame(minWidth: 680, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .showShouxiaWindow)) { _ in
            openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        }
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 14) {
                ReceiveMark(size: 43).foregroundStyle(Ink.dark)
                    .background(Ink.mint).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text("收下").font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(2).foregroundStyle(.white)
                    Text("喜欢的内容，留在身边。")
                        .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.74))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(store.connection.isReady ? Ink.mint : Color.orange).frame(width: 6, height: 6)
                    Text(store.connection.label).font(.system(size: 11, weight: .medium))
                }.foregroundStyle(.white.opacity(0.9))
                Text("本机处理 · 本机保存").font(.system(size: 10)).foregroundStyle(.white.opacity(0.66))
            }
        }
        .padding(.horizontal, 30).padding(.top, 39).padding(.bottom, 25)
        .background(Ink.dark)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(dragOver ? "松手，就交给收下。" : "添加一个链接")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("支持视频与音频").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            HStack(spacing: 12) {
                Image(systemName: dragOver ? "arrow.down.to.line" : "link")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Ink.muted)
                TextField("粘贴视频链接，或拖到这里", text: $input)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .focused($inputFocused).onSubmit { submit() }
                    .accessibilityLabel("视频链接")
                if !input.isEmpty {
                    GlyphButton(symbol: "xmark.circle.fill", title: "清空链接") { input = ""; inputFocused = true }
                } else {
                    Button("粘贴") { paste() }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.dark)
                }
            }
            .padding(.horizontal, 15).frame(height: 55)
            .background(dragOver ? Ink.mint.opacity(0.3) : Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(dragOver || inputFocused ? Ink.dark : Ink.line, lineWidth: dragOver ? 2 : 1))
            .onDrop(of: [.url, .plainText], isTargeted: $dragOver, perform: acceptDrop)
            HStack(spacing: 12) {
                Picker("下载类型", selection: $audioOnly) {
                    Text("视频").tag(false)
                    Text("仅音频").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                if !audioOnly {
                    Menu {
                        Button("最佳画质") { quality = "best" }
                        Button("1080p") { quality = "1080" }
                        Button("720p") { quality = "720" }
                        Button("480p") { quality = "480" }
                    } label: {
                        HStack(spacing: 5) {
                            Text(quality == "best" ? "最佳画质" : quality + "p")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).frame(height: 30)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("选择最高下载清晰度；直链文件保留原始画质")
                } else {
                    Text("MP3").font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 8)
                if store.isSubmitting { ProgressView().controlSize(.small) }
                Button(action: submit) {
                    HStack(spacing: 10) {
                        Text(store.isSubmitting ? "正在解析" : "收下")
                        Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold))
                    }.frame(minWidth: 72)
                }
                .buttonStyle(SoftButtonStyle(primary: true))
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSubmitting || !store.connection.isReady)
                .keyboardShortcut(.return, modifiers: .command)
                .help("开始下载 ⌘↩")
            }
            if store.isSubmitting {
                Text("正在读取标题和可下载格式，部分平台需要稍等片刻…")
                    .font(.system(size: 11)).foregroundStyle(Ink.muted)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.isSubmitting)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: dragOver)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Text("收集记录").font(.system(size: 16, weight: .semibold))
                Spacer()
                ForEach(["全部", "进行中", "已完成"], id: \.self) { name in
                    Button { filter = name } label: {
                        Text(name).font(.system(size: 11, weight: filter == name ? .semibold : .regular))
                            .foregroundStyle(filter == name ? Ink.dark : Ink.muted)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(filter == name ? Ink.dark.opacity(0.065) : .clear)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(visibleItems) { item in
                        TaskRow(item: item, store: store, pending: store.pending.contains { $0.url == item.url })
                    }
                    if empty { emptyState }
                }.padding(.bottom, 12)
            }.scrollIndicators(.automatic)
        }.frame(maxHeight: .infinity)
    }

    private var visibleItems: [DownloadItem] {
        let candidates: [DownloadItem]
        if filter == "进行中" { candidates = store.items + store.pending }
        else if filter == "已完成" { candidates = store.completed.filter(\.isComplete) }
        else { candidates = store.items + store.pending + store.completed }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.url).inserted }
    }
    private var empty: Bool { visibleItems.isEmpty }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == "进行中" ? "checkmark.circle" : "tray")
                .font(.system(size: 33, weight: .ultraLight)).foregroundStyle(Ink.muted)
            Text(filter == "进行中" ? "此刻没有下载任务" : "下一份喜欢，从一个链接开始。")
                .font(.system(size: 13, weight: .medium))
            Text("YouTube · Bilibili · 抖音 · X 等平台\n可用性取决于视频权限与平台限制")
                .font(.system(size: 11)).foregroundStyle(Ink.muted).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder").font(.system(size: 11))
            Button("下载 / MeTube") { FileActions.revealFolder() }.buttonStyle(.plain).help("打开下载文件夹")
            Spacer()
            if !store.connection.isReady {
                Button("重新连接") { Task { await store.reconnect() } }.buttonStyle(.plain)
                    .disabled(store.connection == .starting || store.connection == .connecting)
            }
            GlyphButton(symbol: "arrow.clockwise", title: "刷新任务") { Task { await store.refresh() } }
            GlyphButton(symbol: "questionmark.circle", title: "使用说明") { FileActions.showHelp() }
        }
        .font(.system(size: 11)).foregroundStyle(Ink.muted)
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(Ink.paper)
    }
    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
            Text(text).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { store.message = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("关闭提示")
        }.foregroundStyle(Ink.danger).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.danger.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 9))
    }
    private func submit() {
        guard !store.isSubmitting else { return }
        let captured = input
        Task {
            if await store.submit(captured, quality: quality, audioOnly: audioOnly), input == captured {
                input = ""; filter = "全部"
            }
        }
    }
    private func paste() {
        if let text = NSPasteboard.general.string(forType: .string) { input = text; inputFocused = true }
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in input = url.absoluteString; inputFocused = true }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let value = value as? String else { return }
                Task { @MainActor in input = value; inputFocused = true }
            }
            return true
        }
        return false
    }
}

struct QuickPanel: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.openWindow) private var openWindow
    @State private var input = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                ReceiveMark(size: 30).background(Ink.mint).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("收下").font(.system(size: 18, weight: .bold))
                Spacer()
                Text(store.connection.label).font(.system(size: 10)).foregroundStyle(Ink.muted)
            }
            HStack {
                TextField("粘贴视频链接", text: $input).textFieldStyle(.plain).onSubmit { submit() }
                Button { input = NSPasteboard.general.string(forType: .string) ?? "" } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.plain).help("粘贴链接").accessibilityLabel("粘贴链接")
            }.padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius: 9))
            Button(action: submit) {
                HStack { Text(store.isSubmitting ? "正在解析…" : "收下 · 1080p"); Spacer(); Image(systemName: "arrow.down") }
            }.buttonStyle(SoftButtonStyle(primary: true))
                .disabled(input.isEmpty || store.isSubmitting || !store.connection.isReady)
            if let message = store.message { Text(message).font(.system(size: 11)).foregroundStyle(Ink.danger).lineLimit(3) }
            if let active = store.items.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(active.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    ProgressView(value: min(100, max(0, active.percent ?? 0)), total: 100).tint(Ink.dark)
                    Text("\(store.items.count) 个下载任务").font(.system(size: 10)).foregroundStyle(Ink.muted)
                }
            } else {
                Text("文件保存在 下载 / MeTube").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            HStack {
                Button("打开主窗口") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("打开下载文件夹") { FileActions.revealFolder() }
                    Button("使用说明") { FileActions.showHelp() }
                    Divider()
                    Button("退出收下（下载继续）") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.font(.system(size: 12, weight: .medium))
        }.padding(20).frame(width: 330).foregroundStyle(Ink.dark).background(Ink.paper)
            .task { store.start() }
    }
    private func submit() {
        let captured = input
        Task { if await store.submit(captured, quality: "1080", audioOnly: false), input == captured { input = "" } }
    }
}
