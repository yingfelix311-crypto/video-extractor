import SwiftUI
import AVKit
import UniformTypeIdentifiers

@MainActor final class ClipEditorModel: ObservableObject {
    let source: URL
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published private(set) var playbackSpeed: Float = 1
    @discardableResult func setPlaybackSpeed(_ value: Double) -> Bool {
        guard value.isFinite, (0.25...2).contains(value) else { return false }
        playbackSpeed = Float(value)
        if player.timeControlStatus != .paused { player.rate = playbackSpeed }
        return true
    }
    private var playbackObservation: NSKeyValueObservation?
    @Published var canvas: ClipCanvas = .source
    @Published private(set) var geometry: ClipGeometry?
    @Published var duration = 0.0
    @Published var position = 0.0
    @Published var startText = "00:00:00.000"
    @Published var endText = "00:00:00.000"
    @Published var error: String?
    @Published var loading = true
    @Published var exporting = false
    @Published var progress = 0.0
    @Published var result: URL?
    @Published var notice: String?
    private var observer: Any?
    private var previewEnd: Double?
    private var revision = 0
    private let exporter = ClipExporter()
    init(source: URL) {
        self.source = source
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor [weak self] in self?.isPlaying = playing }
        }
    }
    func togglePlayback() {
        if player.timeControlStatus != .paused { resetPreview() }
        else {
            resetPreview()
            if position >= duration - 0.01 { seek(0) }
            player.playImmediately(atRate: playbackSpeed)
        }
    }
    func moveBoundary(_ seconds: Double, start: Bool) {
        guard duration > 0 else { return }
        let limit = (duration * 1000).rounded(.down) / 1000
        let currentStart = min(limit, max(0, ClipRange.parse(startText) ?? 0))
        let currentEnd = min(limit, max(0.001, ClipRange.parse(endText) ?? limit))
        let value = (seconds * 1000).rounded() / 1000
        let bounded = start ? min(max(0, value), max(0, currentEnd - 0.001)) : max(min(limit, value), min(limit, currentStart + 0.001))
        resetPreview()
        if start { startText = ClipRange.format(bounded) } else { endText = ClipRange.format(bounded) }
        seek(bounded)
    }
    var range: ClipRange? {
        guard let start = ClipRange.parse(startText), let end = ClipRange.parse(endText) else { return nil }
        return try? ClipRange(start: start, end: end, duration: duration)
    }
    func load() async {
        do {
            let asset = AVURLAsset(url: source)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0, !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                throw AppError.message("无法读取视频时长或视频轨道，请选择其他文件。")
            }
            guard !Task.isCancelled else { return }
            let track = try await asset.loadTracks(withMediaType: .video)[0]
            let geometry = ClipGeometry(naturalSize: try await track.load(.naturalSize), preferredTransform: try await track.load(.preferredTransform))
            guard geometry.isValid else { throw AppError.message("无法读取视频尺寸。") }
            self.geometry = geometry
            duration = seconds
            endText = ClipRange.format(min(10, (seconds * 1000).rounded(.down) / 1000))
            let item = AVPlayerItem(asset: asset)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.position = min(self.duration, max(0, time.seconds.isFinite ? time.seconds : 0))
                    if let end = self.previewEnd, self.position >= end {
                        self.player.pause(); self.previewEnd = nil
                    }
                }
            }
        } catch { self.error = "无法打开视频：\(error.localizedDescription)" }
        loading = false
    }
    func seek(_ value: Double) {
        revision += 1; previewEnd = nil; player.pause()
        position = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func mark(start: Bool) {
        let value = min(duration, max(0, player.currentTime().seconds))
        let text = ClipRange.format((value * 1000).rounded(.down) / 1000)
        if start { startText = text } else { endText = text }
    }
    func preview() {
        guard let range else { return }
        seek(range.start)
        previewEnd = range.end
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: range.end, preferredTimescale: 60000)
        let token = revision
        player.seek(to: CMTime(seconds: range.start, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, finished, self.revision == token else { return }
                self.player.playImmediately(atRate: self.playbackSpeed)
            }
        }
    }
    func resetPreview() {
        revision += 1; previewEnd = nil; player.pause()
        player.currentItem?.forwardPlaybackEndTime = .invalid
    }
    func save() {
        guard let range, !exporting else { return }
        let exportSpeed = Double(playbackSpeed)
        let exportCanvas = canvas
        resetPreview()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.title = "导出片段"; panel.prompt = "导出"
        panel.directoryURL = source.deletingLastPathComponent()
        let start = ClipRange.format(range.start).replacingOccurrences(of: ":", with: "-")
        let end = ClipRange.format(range.end).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(source.deletingPathExtension().lastPathComponent)_\(start)_\(end).mp4"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        exporting = true; progress = 0; error = nil; notice = nil; result = nil
        Task {
            let monitor = Task { @MainActor in
                while !Task.isCancelled {
                    progress = exporter.progress
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { monitor.cancel(); exporting = false }
            do {
                try await exporter.export(source: source, target: target, range: range, speed: exportSpeed, canvas: exportCanvas)
                progress = 1; result = target
            } catch is CancellationError { notice = "已取消导出，原视频未改动。" }
            catch { self.error = "导出失败：\(error.localizedDescription)" }
        }
    }
    func cancel() { exporter.cancel() }
    func close() {
        resetPreview()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
        player.replaceCurrentItem(with: nil)
    }
}

struct ClipPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}

struct ClipTimeline: View {
    @ObservedObject var model: ClipEditorModel
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 32)
            let duration = max(0.001, model.duration)
            let start = min(duration, max(0, ClipRange.parse(model.startText) ?? 0))
            let end = min(duration, max(start, ClipRange.parse(model.endText) ?? duration))
            let left = 16 + width * start / duration
            let right = 16 + width * end / duration
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(Ink.surface)
                    .frame(width: width, height: 32).offset(x: 16, y: 24)
                RoundedRectangle(cornerRadius: 5).fill(Ink.mint.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.mint, lineWidth: 1))
                    .frame(width: max(1, right - left), height: 32).offset(x: left, y: 24)
                Rectangle().fill(Ink.dark).frame(width: 2, height: 24)
                    .offset(x: 15 + width * min(1, max(0, model.position / duration)), y: 28)
                    .allowsHitTesting(false)
                Color.clear.frame(width: width, height: 32).contentShape(Rectangle()).offset(x: 16, y: 24)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("clipTimeline"))
                        .onChanged { value in
                            model.resetPreview()
                            model.seek(min(duration, max(0, (value.location.x - 16) / width * duration)))
                        })
                handle(start: true, x: left, width: width, duration: duration)
                handle(start: false, x: right, width: width, duration: duration)
            }.coordinateSpace(name: "clipTimeline")
        }.frame(height: 82)
    }
    private func handle(start: Bool, x: Double, width: Double, duration: Double) -> some View {
        VStack(spacing: 4) {
            if start { Text("开始").font(TypeStyle.body(10)).foregroundStyle(Ink.mint) }
            RoundedRectangle(cornerRadius: 4).fill(Ink.mint)
                .overlay(Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90)).font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.paper))
                .frame(width: 14, height: 36)
            if !start { Text("结束").font(TypeStyle.body(10)).foregroundStyle(Ink.mint) }
        }
        .frame(width: 32).contentShape(Rectangle())
        .offset(x: x - 16, y: start ? 6 : 22)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("clipTimeline"))
            .onChanged { value in model.moveBoundary((value.location.x - 16) / width * duration, start: start) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(start ? "片段开始节点" : "片段结束节点")
        .accessibilityValue(start ? model.startText : model.endText)
        .accessibilityAdjustableAction { direction in
            let value = ClipRange.parse(start ? model.startText : model.endText) ?? 0
            model.moveBoundary(value + (direction == .increment ? 0.1 : -0.1), start: start)
        }
    }
}

struct ClipSpeedControl: View {
    @ObservedObject var model: ClipEditorModel
    @State private var showing = false
    @State private var custom = "1"
    @State private var invalid = false
    private var label: String { String(format: "%g×", model.playbackSpeed) }
    var body: some View {
        Button { custom = String(format: "%g", model.playbackSpeed); invalid = false; showing.toggle() } label: {
            HStack(spacing: 5) { Text(label).monospacedDigit(); Image(systemName: "chevron.down").font(.system(size: 9)) }
                .padding(.horizontal, 10).padding(.vertical, 5).background(Ink.surface).clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).foregroundStyle(Ink.mint).accessibilityLabel("播放倍速，当前 \(label)")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 14) {
                Text("播放倍速").font(TypeStyle.heading(16))
                HStack(spacing: 6) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button(String(format: "%g×", speed)) {
                            model.setPlaybackSpeed(speed); showing = false
                        }.buttonStyle(.plain).padding(7)
                            .background(abs(Double(model.playbackSpeed) - speed) < 0.001 ? Ink.purple : Ink.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                HStack {
                    Text("自定义").foregroundStyle(Ink.muted)
                    TextField("0.25–2", text: $custom).textFieldStyle(.roundedBorder).frame(width: 85)
                        .onSubmit { apply() }.accessibilityLabel("自定义播放倍速")
                    Text("×")
                    Button("应用") { apply() }.buttonStyle(SoftButtonStyle(primary: true))
                }
                Text(invalid ? "请输入 0.25 到 2 之间的数字。" : "预览和导出都使用当前倍速。")
                    .font(TypeStyle.body(11)).foregroundStyle(invalid ? Ink.danger : Ink.muted)
            }.font(TypeStyle.body(12)).padding(18).background(Ink.paper).foregroundStyle(Ink.dark).preferredColorScheme(.dark)
        }
    }
    private func apply() {
        guard let value = Double(custom.trimmingCharacters(in: .whitespacesAndNewlines)), model.setPlaybackSpeed(value) else { invalid = true; return }
        showing = false
    }
}

struct ClipEditorView: View {
    @ObservedObject var model: ClipEditorModel
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "scissors").font(.system(size: 22)).foregroundStyle(Ink.mint)
                    .frame(width: 46, height: 46).background(Ink.purple).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("截取片段").font(TypeStyle.heading(22))
                    Text(model.source.lastPathComponent).font(TypeStyle.body(11)).foregroundStyle(Ink.muted).lineLimit(1).help(model.source.path)
                }
                Spacer()
                Text("保留喜欢的这一段").font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
            }
            HStack {
                Picker("画面尺寸", selection: $model.canvas) {
                    ForEach(ClipCanvas.allCases) { canvas in Text(canvas.label).tag(canvas) }
                }.frame(maxWidth: 360).disabled(model.loading || model.exporting)
                Spacer()
                if let geometry = model.geometry {
                    let size = model.canvas.size(for: geometry)
                    Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded()))")
                        .font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                }
            }
            GeometryReader { proxy in
                let size = model.geometry.map { model.canvas.size(for: $0) } ?? CGSize(width: 16, height: 9)
                let fitted = ClipGeometry.fit(size: size, inside: proxy.size)
                ZStack {
                    Color.black
                    ClipPlayer(player: model.player)
                    if model.loading { ProgressView().tint(Ink.mint) }
                }.frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 260)
            Text("预览与导出使用相同尺寸；完整保留画面，空余区域填黑。")
                .font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            VStack(spacing: 10) {
                ClipTimeline(model: model)
                    .disabled(model.loading || model.exporting || model.duration == 0)
                HStack {
                    Button { model.togglePlayback() } label: { Label(model.isPlaying ? "暂停" : "播放", systemImage: model.isPlaying ? "pause.fill" : "play.fill") }
                    .frame(width: 58, alignment: .leading)
                    ClipSpeedControl(model: model)
                    Spacer()
                    Text("\(ClipRange.format(model.position)) / \(ClipRange.format(model.duration))").monospacedDigit().foregroundStyle(Ink.muted)
                }.font(TypeStyle.body(11)).buttonStyle(.plain).disabled(model.loading || model.exporting)
            }
            HStack(spacing: 14) {
                timeField("开始时间", text: $model.startText, start: true)
                Image(systemName: "arrow.right").foregroundStyle(Ink.muted)
                timeField("结束时间", text: $model.endText, start: false)
            }.disabled(model.loading || model.exporting || model.duration == 0)
            HStack {
                if let range = model.range {
                    Text("选中 \(String(format: "%.3f", range.length)) 秒 · \(String(format: "%g", model.playbackSpeed))× · 导出约 \(String(format: "%.2f", range.length / Double(model.playbackSpeed))) 秒").foregroundStyle(Ink.mint)
                } else if !model.loading && model.duration > 0 {
                    Text("请输入有效起止时间，结束时间须晚于开始时间且不超出总时长。").foregroundStyle(Ink.danger)
                }
                Spacer()
                Text("时:分:秒.毫秒").foregroundStyle(Ink.muted)
            }.font(TypeStyle.body(11))
            Rectangle().fill(Ink.line).frame(height: 1)
            if let error = model.error { Text(error).font(TypeStyle.body(12)).foregroundStyle(Ink.danger).textSelection(.enabled) }
            if let notice = model.notice { Text(notice).font(TypeStyle.body(12)).foregroundStyle(Ink.muted) }
            if model.exporting {
                HStack(spacing: 14) {
                    ProgressView(value: model.progress).tint(Ink.mint)
                    Text("导出中 \(Int(model.progress * 100))%").font(TypeStyle.body(12)).monospacedDigit().fixedSize()
                    Button("取消导出") { model.cancel() }.buttonStyle(SoftButtonStyle())
                }
            } else if let result = model.result {
                HStack {
                    Label("片段已保存", systemImage: "checkmark.circle.fill").foregroundStyle(Ink.mint)
                    Spacer()
                    Button("打开片段") { NSWorkspace.shared.open(result) }.buttonStyle(SoftButtonStyle())
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([result]) }.buttonStyle(SoftButtonStyle())
                }.font(TypeStyle.body())
            }
            HStack {
                Text("导出为新的 MP4 文件，原视频保持不变。")
                    .font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                Spacer()
                Button("预览片段") { model.preview() }.buttonStyle(SoftButtonStyle())
                Button("导出片段 ↗") { model.save() }.buttonStyle(SoftButtonStyle(primary: true))
            }.disabled(model.range == nil || model.loading || model.exporting)
        }
        .padding(26).frame(maxWidth: .infinity)
        }.frame(minWidth: 640, minHeight: 480).background(Ink.paper).foregroundStyle(Ink.dark)
        .preferredColorScheme(.dark)
        .task { await model.load() }
        .onChange(of: model.startText) { _, _ in model.resetPreview() }
        .onChange(of: model.endText) { _, _ in model.resetPreview() }
    }
    private func timeField(_ title: String, text: Binding<String>, start: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                Spacer()
                Button("使用当前画面") { model.mark(start: start) }.font(TypeStyle.body(11)).foregroundStyle(Ink.mint).buttonStyle(.plain)
                    .accessibilityLabel(start ? "将当前画面设为开始时间" : "将当前画面设为结束时间")
            }
            TextField(title, text: text).textFieldStyle(.plain).font(TypeStyle.heading(20)).monospacedDigit().accessibilityLabel(title)
        }.padding(14).background(Ink.surface).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor final class ClipWindow: NSObject, NSWindowDelegate {
    static let shared = ClipWindow()
    private var window: NSWindow?
    private var model: ClipEditorModel?
    func choose() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel(); panel.title = "选择要截取的视频"
        panel.allowedContentTypes = [.movie]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        show(url)
    }
    func show(_ source: URL?) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        guard let source, FileManager.default.fileExists(atPath: source.path) else { choose(); return }
        let model = ClipEditorModel(source: source)
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "截取片段 · Video Extractor"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Ink.paper)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: ClipEditorView(model: model))
        window.isReleasedWhenClosed = false; window.delegate = self
        self.window = window
        window.minSize = NSSize(width: 640, height: 480)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setContentSize(NSSize(width: min(800, visible.width - 40), height: min(800, visible.height - 70)))
        }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model?.exporting == true else { return true }
        let alert = NSAlert(); alert.messageText = "片段正在导出"
        alert.informativeText = "取消后可重新导出，原视频不会改变。"
        alert.addButton(withTitle: "继续导出"); alert.addButton(withTitle: "取消导出")
        if alert.runModal() == .alertSecondButtonReturn { model?.cancel() }
        return false
    }
    func windowWillClose(_ notification: Notification) { model?.close(); model = nil; window = nil }
}
