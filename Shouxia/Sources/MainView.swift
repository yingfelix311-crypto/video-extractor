import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var store: DownloadStore
    @ObservedObject var updater: EngineUpdater
    @Environment(\.openWindow) private var openWindow
    @State private var input = ""
    @AppStorage("downloadQuality") private var quality = "best"
    @AppStorage("downloadAudioOnly") private var audioOnly = false
    @State private var dragOver = false
    @State private var filter = "全部"
    @State private var mediaFilter = "全部媒体"
    @State private var managingHistory = false
    @State private var selectedHistory = Set<String>()
    @FocusState private var inputFocused: Bool
    init(store:DownloadStore) { self.store=store; self.updater=store.updater }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:9) {
                    Text("Video Extractor").font(TypeStyle.heading(29)).tracking(-1.2)
                    Text("把喜欢的片段，带回来。").font(TypeStyle.body(13)).foregroundStyle(Ink.muted)
                }
                Spacer()
                ReceiveMark(size:68).accessibilityHidden(true)
            }.padding(.top,37).padding(.bottom,26)
            HStack(spacing:12) {
                HStack(spacing:12) {
                    Image(systemName:"link").foregroundStyle(Ink.muted)
                    TextField("粘贴视频链接",text:$input).textFieldStyle(.plain).font(TypeStyle.body(15)).focused($inputFocused).onSubmit(submit).onExitCommand(perform:clearInput).accessibilityLabel("视频链接")
                    ClearLinkButton(isEmpty:input.isEmpty,label:"清空视频链接",action:clearInput)
                    Button("粘贴") { input=NSPasteboard.general.string(forType:.string) ?? ""; inputFocused=true }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                }.padding(.horizontal,16).frame(height:58).background(Ink.surface).clipShape(RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(dragOver ? Ink.mint : Ink.line,lineWidth:1))
                    .onDrop(of:[.url,.plainText],isTargeted:$dragOver,perform:acceptDrop)
                Button(action:submit) { HStack(spacing:14) { Text(store.isSubmitting ? "解析中" : "提取"); Image(systemName:"arrow.up.right") }.frame(height:36) }
                    .buttonStyle(SoftButtonStyle(primary:true)).disabled(input.isEmpty || store.isSubmitting || store.isConfiguring || updater.isUpdating || !store.connection.isReady)
            }
            HStack(spacing:20) {
                FormatControl(audioOnly:$audioOnly)
                QualityControl(quality:$quality).disabled(audioOnly)
                Button(audioOnly ? "MP3" : (store.options.videoFormat == "mp4" ? "MP4 源格式" : "原始最佳格式")) { store.showSettings=true }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.muted).accessibilityLabel("设置下载格式")
                Spacer()
                Button("快速上手") { store.showSettings=false; store.showQuickStart=true }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                Button("快捷输入") { QuickWindow.shared.show(store:store) }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            }.padding(.top,14)
            DestinationControl(store:store).padding(.top,15).padding(.bottom,23)
            if let notice=store.notice {
                HStack { Text(notice).font(TypeStyle.body(11)).foregroundStyle(Ink.mint); Spacer(); GlyphButton(symbol:"xmark",title:"关闭成功提示") { store.notice=nil } }.padding(.bottom,12)
            }
            if let message=standaloneMessage {
                HStack(alignment:.top) { FailureDetails(raw:message,store:store); Spacer(); GlyphButton(symbol:"xmark",title:"关闭提示") { store.message=nil } }
                    .foregroundStyle(Ink.danger).padding(10).background(Ink.surface).clipShape(RoundedRectangle(cornerRadius:9)).padding(.bottom,12)
            }
            HStack {
                Picker("任务媒体",selection:$mediaFilter) { ForEach(["全部媒体","视频","音频"],id:\.self) { Text($0) } }.labelsHidden().frame(width:116).accessibilityLabel("筛选任务媒体"); Text("/ \(visibleItems.count)").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                Spacer()
                ForEach(["全部","进行中","已完成","失败"],id:\.self) { name in
                    Button(name == "失败" ? "失败 \(failedCount)" : name) { filter=name }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(filter==name ? Ink.dark : Ink.muted)
                }
                Button(managingHistory ? "完成管理" : "管理记录") {
                    managingHistory.toggle(); selectedHistory.removeAll()
                }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.mint)
                    .disabled(!managingHistory && removableIDs.isEmpty)
            }.padding(.bottom,14)
            if managingHistory {
                HStack(spacing: 14) {
                    Button(!removableIDs.isEmpty && selectedHistory == removableIDs ? "取消全选" : "全选当前列表") {
                        selectedHistory = selectedHistory == removableIDs ? [] : removableIDs
                    }.disabled(removableIDs.isEmpty)
                    Text("仅移除记录，保留下载文件").foregroundStyle(Ink.muted)
                    Spacer()
                    Button("删除所选（\(selectedHistory.count)）") {
                        let ids = selectedHistory
                        Task { if await store.clearHistory(ids: ids) { selectedHistory.subtract(ids) } }
                    }.foregroundStyle(Ink.danger).disabled(selectedHistory.isEmpty || store.isSubmitting || updater.isUpdating)
                }.buttonStyle(.plain).font(TypeStyle.body(11)).padding(.bottom,12)
            }
            Rectangle().fill(Ink.line).frame(height:1)
            ScrollView {
                LazyVStack(spacing:0) {
                    ForEach(visibleSubmissions) { intent in SubmissionRow(intent:intent,store:store) }
                    ForEach(visibleItems) { item in
                        HStack(spacing: 12) {
                            if managingHistory {
                                if removableIDs.contains(item.id) {
                                    Button {
                                        if !selectedHistory.insert(item.id).inserted { selectedHistory.remove(item.id) }
                                    } label: {
                                        Image(systemName: selectedHistory.contains(item.id) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selectedHistory.contains(item.id) ? Ink.mint : Ink.muted)
                                    }.buttonStyle(.plain).accessibilityLabel("选择记录：\(item.title)")
                                } else { Color.clear.frame(width: 14, height: 14) }
                            }
                            TaskRow(item:item,store:store,pending:!item.isArchived && store.pending.contains{$0.url==item.url})
                        }
                    }
                    if visibleItems.isEmpty && visibleSubmissions.isEmpty {
                        VStack(spacing:12) { ReceiveMark(size:62); Text(filter == "全部" ? "暂无任务，粘贴链接开始。" : "暂无\(filter)任务").font(TypeStyle.body(13)).foregroundStyle(Ink.muted) }.frame(maxWidth:.infinity).padding(.vertical,35)
                    }
                }
            }.frame(maxHeight:.infinity)
            HStack(spacing:8) {
                Circle().fill(store.connection.isReady ? Ink.mint : Ink.muted).frame(width:5,height:5)
                Text(updater.isUpdating ? updater.status : store.connection.label).lineLimit(1)
                if !store.connection.isReady && !updater.isUpdating { Button("重新连接") { Task { await store.reconnect() } }.buttonStyle(.plain) }
                Spacer()
                GlyphButton(symbol:"folder",title:"打开保存文件夹") { FileActions.revealFolder(store.destinationPath) }
                GlyphButton(symbol:"arrow.clockwise",title:"刷新任务") { Task { await store.refresh() } }
                GlyphButton(symbol:"gearshape",title:"设置与更新") { store.showSettings=true }
            }.font(TypeStyle.body(11)).foregroundStyle(Ink.muted).padding(.vertical,12)
        }.padding(.horizontal,32).foregroundStyle(Ink.dark).background(Ink.paper)
            .frame(minWidth:860,minHeight:710)
            .sheet(isPresented:$store.showSettings) { EngineSettings(store:store,updater:updater) }
            .sheet(isPresented:$store.showQuickStart,onDismiss:{
                if store.quickStartOpenSettings {store.quickStartOpenSettings=false;store.showSettings=true}
            }) { QuickStartView(store:store,updater:updater) }
            .onAppear { inputFocused=true }
            .onChange(of: audioOnly) { _, _ in selectedHistory.removeAll() }
            .onChange(of: filter) { _, _ in selectedHistory.removeAll() }
            .onChange(of: removableIDs) { _, ids in selectedHistory.formIntersection(ids) }
            .onReceive(NotificationCenter.default.publisher(for:.showShouxiaWindow)) { _ in openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }
    }
    private var visibleItems:[DownloadItem] {
        TaskList.visible(active: store.items, pending: store.pending, history: store.completed, audioOnly: mediaFilter == "全部媒体" ? nil : mediaFilter == "音频", filter: filter)
    }
    private var standaloneMessage:String? {
        guard let message=store.message,
              !store.submissions.contains(where:{$0.error==message}),
              !store.completed.contains(where:{$0.isFailed && ($0.error ?? $0.msg)==message}) else {return nil}
        return message
    }
    private var failedCount:Int { store.completed.filter(\.isFailed).count + store.submissions.filter { $0.state == .failed }.count }
    private var visibleSubmissions:[SubmissionIntent] {
        store.submissions.filter { intent in
            (mediaFilter == "全部媒体" || intent.audioOnly == (mediaFilter == "音频")) && (filter == "全部" || (filter == "失败" ? intent.state == .failed : filter == "进行中" && intent.state != .failed))
        }
    }
    private var removableIDs: Set<String> {
        Set(visibleItems.filter { item in
            store.completed.contains { $0.id == item.id } && store.canRemoveHistory(item)
        }.map(\.id))
    }
    private func clearInput() { input=""; inputFocused=true }
    private func submit() {
        let captured=input
        Task { if await store.submit(captured,quality:quality,audioOnly:audioOnly), input==captured { input=""; filter="全部" } }
    }
    private func acceptDrop(_ providers:[NSItemProvider])->Bool {
        guard let provider=providers.first else {return false}
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _=provider.loadObject(ofClass:URL.self) { url,_ in guard let url else{return}; Task{@MainActor in input=url.absoluteString; inputFocused=true} }; return true
        }
        if provider.canLoadObject(ofClass:NSString.self) {
            _=provider.loadObject(ofClass:NSString.self) { value,_ in guard let value=value as? String else{return}; Task{@MainActor in input=value; inputFocused=true} }; return true
        }
        return false
    }
}
struct ClearLinkButton:View {
    let isEmpty:Bool
    let label:String
    let action:()->Void
    var body:some View {
        Button("清空",action:action)
            .buttonStyle(.plain).font(TypeStyle.medium(11)).foregroundStyle(Ink.mint)
            .frame(minWidth:44,minHeight:30).contentShape(Rectangle())
            .disabled(isEmpty).opacity(isEmpty ? 0.35 : 1)
            .help("清空链接 · Esc").accessibilityLabel(label)
    }
}
struct FormatControl:View {
    @Binding var audioOnly:Bool
    var body:some View {
        HStack(spacing:4) {
            ForEach([false,true],id:\.self) { value in
                Button(value ? "音频" : "视频") { audioOnly=value }.buttonStyle(.plain).font(TypeStyle.medium(12)).foregroundStyle(audioOnly==value ? Ink.dark : Ink.muted).padding(.horizontal,15).padding(.vertical,7).background(audioOnly==value ? Ink.purple : .clear).clipShape(RoundedRectangle(cornerRadius:7))
            }
        }
    }
}
struct QualityControl:View {
    @Binding var quality:String
    @State private var expanded=false
    private var label:String { DownloadQuality.label(for:quality) }
    var body:some View {
        Button { expanded.toggle() } label: { HStack(spacing:13) { Text(label).fixedSize(); Image(systemName:"chevron.down").font(.system(size:9)) }.font(TypeStyle.body(12)).padding(7) }
            .buttonStyle(.plain).accessibilityLabel("画质：\(label)")
            .popover(isPresented:$expanded,arrowEdge:.bottom) {
                VStack(spacing:4) {
                    ForEach(DownloadQuality.values,id:\.self) { value in
                        Button { quality=value; expanded=false } label: { HStack { Text(DownloadQuality.label(for:value)); Spacer(); if quality==value { Image(systemName:"checkmark").foregroundStyle(Ink.mint) } }.font(TypeStyle.body(13)).padding(10).background(quality==value ? Ink.purple : .clear).clipShape(RoundedRectangle(cornerRadius:6)) }.buttonStyle(.plain)
                    }
                    Text("按源站可用画质下载，最高不超过所选档位；不会放大。音频忽略画质。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted).fixedSize(horizontal:false,vertical:true).padding(8)
                }.padding(8).frame(width:240).foregroundStyle(Ink.dark).background(Ink.surface).preferredColorScheme(.dark)
            }
    }
}
struct DestinationControl:View {
    @ObservedObject var store:DownloadStore
    var compact=false
    var body:some View {
        HStack(spacing:9) {
            Text("保存到").foregroundStyle(Ink.muted)
            Button { FileActions.revealFolder(store.destinationPath) } label: { Text((store.destinationPath as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).help(store.destinationPath)
            if !compact { Spacer(minLength:0) }
            Button { FileActions.chooseFolder(store:store) } label: { Label(compact ? "更改" : "更改文件夹",systemImage:"folder") }.buttonStyle(.plain).foregroundStyle(Ink.muted).fixedSize()
        }.font(TypeStyle.body(11)).foregroundStyle(Ink.dark)
    }
}
struct QuickPanel:View {
    @ObservedObject var store:DownloadStore
    @ObservedObject var updater:EngineUpdater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var input=""
    @AppStorage("downloadQuality") private var quality="best"
    @AppStorage("downloadAudioOnly") private var audioOnly=false
    @FocusState private var focused:Bool
    init(store:DownloadStore) { self.store=store; self.updater=store.updater }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                HStack(spacing:8) {
                    TextField("粘贴视频链接",text:$input)
                        .textFieldStyle(.plain).font(TypeStyle.body(13)).focused($focused)
                        .onSubmit(submit).accessibilityLabel("快捷视频链接")
                    ClearLinkButton(isEmpty:input.isEmpty,label:"清空快捷视频链接",action:clearInput)
                }.padding(.horizontal,12).frame(height:38)
                    .background(Ink.surface).clipShape(RoundedRectangle(cornerRadius:10))
                Button(action:submit) {
                    Image(systemName:store.isSubmitting ? "hourglass" : "arrow.up.right").frame(width:12,height:16)
                }.buttonStyle(SoftButtonStyle(primary:true)).fixedSize()
                    .accessibilityLabel(store.isSubmitting ? "正在解析" : "提取")
                    .help("提取 · 回车")
                    .disabled(input.isEmpty || store.isSubmitting || store.isConfiguring || updater.isUpdating || !store.connection.isReady)
            }
            HStack { FormatControl(audioOnly:$audioOnly); QualityControl(quality:$quality).disabled(audioOnly) }
            Text(audioOnly ? "音频 · MP3" : "视频 · \(store.options.videoFormat == "mp4" ? "MP4 源格式" : "原始最佳格式")").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            if let notice=store.notice {
                Text(notice).font(TypeStyle.body(11)).foregroundStyle(Ink.mint)
            }
            Button("查看任务") { openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.mint)
            HStack(spacing:8) {
                Image(systemName:"folder").foregroundStyle(Ink.muted)
                Button { FileActions.revealFolder(store.destinationPath) } label: {
                    Text(URL(fileURLWithPath:store.destinationPath).lastPathComponent).lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.plain).help(store.destinationPath)
                Spacer(minLength:0)
                Button("更改") { FileActions.chooseFolder(store:store) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).fixedSize()
            }.font(TypeStyle.body(11))
            if let message=store.message {
                FailureDetails(raw:message,store:store)
            } else if !store.connection.isReady || updater.isUpdating {
                HStack {
                    Text(updater.isUpdating ? updater.status : store.connection.label)
                    if !store.connection.isReady && !updater.isUpdating {
                        Button("重新连接") { Task { await store.reconnect() } }.buttonStyle(.plain)
                    }
                }.font(TypeStyle.body(10)).foregroundStyle(Ink.muted)
            }
        }.padding(14).frame(width:320).foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
            .onAppear { focused=true; store.start() }.onExitCommand {
                if !input.isEmpty {clearInput()} else {QuickWindow.shared.hide(); dismiss()}
            }
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("focusQuickInput"))) { _ in
                focused=false
                DispatchQueue.main.async { focused=true }
            }
    }
    private func clearInput() {input="";focused=true}
    private func submit() {
        let captured=input
        Task { if await store.submit(captured,quality:quality,audioOnly:audioOnly),input==captured { input="" } }
    }
}
@MainActor final class QuickWindow {
    static let shared=QuickWindow()
    private var panel:NSPanel?
    func show(store:DownloadStore) {
        if panel==nil {
            let panel=InputPanel(contentRect:NSRect(x:0,y:0,width:320,height:110),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
            panel.title="快捷提取"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent=true
            panel.isReleasedWhenClosed=false; panel.level = .floating; panel.isMovableByWindowBackground=true
            let content=NSHostingView(rootView:QuickPanel(store:store))
            content.sizingOptions = [.preferredContentSize]
            panel.contentView=content
            panel.setContentSize(content.fittingSize)
            panel.center(); self.panel=panel
        }
        NSApp.activate(ignoringOtherApps:true); panel?.center(); panel?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { NotificationCenter.default.post(name:Notification.Name("focusQuickInput"),object:nil) }
    }
    func hide() { panel?.orderOut(nil) }
}
final class InputPanel:NSPanel { override var canBecomeKey:Bool {true}; override var canBecomeMain:Bool {true} }
