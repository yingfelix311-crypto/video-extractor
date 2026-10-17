import Foundation

@main struct CoreTests {
    static func main() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
        check(try! LinkParser.extract("复制这条 https://v.douyin.com/AbC123/ 打开抖音") == "https://v.douyin.com/AbC123/", "share text")
        check(try! LinkParser.extract("https://youtu.be/abc。") == "https://youtu.be/abc", "trailing punctuation")
        for text in ["hello", "file:///tmp/a", "https:///missing", "http://localhost/test", "http://127.0.0.1", "http://192.168.0.1", "http://[::1]/", "https://a.com https://b.com"] {
            check((try? LinkParser.extract(text)) == nil, "must reject \(text)")
        }
        let resolved = try LinkParser.resolve("分享 https://www.douyin.com/jingxuan?modal_id=123456")
        check(resolved.originalURL == "https://www.douyin.com/jingxuan?modal_id=123456", "original retained")
        check(resolved.canonicalURL == "https://www.douyin.com/video/123456" && resolved.wasNormalized, "jingxuan normalized")
        check(try! LinkParser.extract("https://douyin.com/?modal_id=42") == "https://www.douyin.com/video/42", "root modal normalized")
        for query in ["modal_id=", "modal_id=abc", "modal_id=-1", "modal_id=1&modal_id=2", "modal_id=" + String(repeating: "1", count: 31)] {
            check((try? LinkParser.resolve("https://www.douyin.com/jingxuan?" + query)) == nil, "invalid modal rejected")
        }
        for link in ["https://foreign.com/jingxuan?modal_id=123", "https://www.douyin.com/live?modal_id=123", "https://www.douyin.com/slides/123?modal_id=123", "https://v.douyin.com/abc/"] {
            check(try! LinkParser.resolve(link).canonicalURL == link, "non video routes preserved")
        }
        let options = try DownloadOptions(videoFormat: "mp4", proxy: "http://localhost:7890", referer: "https://www.douyin.com/", userAgent: "Browser").validated()
        check(options.proxy == "http://host.lima.internal:7890", "Docker localhost mapped")
        check(options.ytdlOverrides["proxy"] == options.proxy && options.ytdlOverrides["referer"] == options.referer && options.ytdlOverrides["user_agent"] == "Browser", "network override keys")
        for proxy in ["file:///tmp/a", "http://user:secret@example.com:80", "http://example.com?a=b", "http://example.com/#fragment"] {
            check((try? DownloadOptions(proxy: proxy).validated()) == nil, "unsafe proxy rejected")
        }
        check((try? DownloadOptions(userAgent: "Agent\r\nInjected: yes").validated()) == nil, "header injection rejected")
        check((try? DownloadOptions(referer: "http://localhost/").validated()) == nil, "private referer rejected")
        check((try? DownloadOptions(videoFormat: "exe").validated()) == nil, "format allowlist")
        check((try? DownloadOptions(referer: "prefix https://example.com/").validated()) == nil, "referer must be a URL rather than share text")
        check(try! JSONDecoder().decode(ResolvedLink.self, from: JSONEncoder().encode(resolved)).canonicalURL == resolved.canonicalURL, "resolved link persistence")
        check(try! JSONDecoder().decode(DownloadOptions.self, from: JSONEncoder().encode(options)) == options, "options persistence")
        let configured = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: "https://youtu.be/a", quality: "best", audioOnly: false, options: options)) as! [String: Any]
        check(configured["format"] as? String == "mp4" && configured["ytdl_options_overrides"] != nil, "explicit format and network options")
        check(DownloadFailure.classify("Unsupported URL: https://www.douyin.com/jingxuan").kind == .unsupportedLink, "unsupported route separate")
        check(DownloadFailure.classify("Fresh cookies are needed").kind == .cookies, "fresh cookie diagnosis")
        check(DownloadFailure.classify("HTTP Error 403: Forbidden").kind == .network, "403 alone is not cookie diagnosis")
        for (raw, kind) in [("Requested format is not available", DownloadFailure.Kind.format), ("Permission denied", .permission), ("下载服务未启动", .service), ("cancelled", .cancelled), ("unrecognized error", .unknown)] {
            check(DownloadFailure.classify(raw).kind == kind, "failure category: \(raw)")
        }
        for url in ["https://example.com/movie.webm", "https://example.com/movie.mov"] {
            let explicitMP4 = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: url, quality: "720", audioOnly: false, options: DownloadOptions(videoFormat: "mp4"))) as! [String: Any]
            check(explicitMP4["format"] as? String == "mp4" && explicitMP4["quality"] as? String == "best", "direct media honors explicit MP4 while retaining source quality")
        }
        check(DownloadFailure.classify("Connection refused by upstream").kind == .network, "generic refused connection is network")
        check(DownloadFailure.classify("HTTP 503 service unavailable").kind == .network, "remote unavailable is network")
        check(DownloadFailure.classify("Connection refused at http://127.0.0.1:8081").kind == .service, "known local backend failure")
        check(DownloadFailure.classify("Backend offline").kind == .service, "explicit backend offline")
        let videoBody = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: "https://youtu.be/a", quality: "480", audioOnly: false)) as! [String: Any]
        check(videoBody["quality"] as? String == "480", "480p must be preserved")
        check(videoBody["format"] as? String == "any", "video format")
        let tagged = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: "https://youtu.be/a", quality: "720", audioOnly: false, folder: "VideoExtractor/test-token")) as! [String: Any]
        check(tagged["folder"] as? String == "VideoExtractor/test-token", "server folder preserves destination identity across URL canonicalization")
        for url in ["https://media.w3.org/2010/05/sintel/trailer.mp4", "https://example.com/movie.WEBM?token=abc", "https://example.com/file.mov", "https://example.com/file.m4v"] {
            let directBody = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: url, quality: "1080", audioOnly: false)) as! [String: Any]
            check(directBody["quality"] as? String == "best", "direct file retains source quality")
            check(directBody["format"] as? String == "any", "direct file retains source container")
        }
        let audioBody = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: "https://youtu.be/a", quality: "480", audioOnly: true)) as! [String: Any]
        check(audioBody["quality"] as? String == "best", "audio quality must match server schema")
        check(audioBody["format"] as? String == "mp3", "audio format")
        check(audioBody["ytdl_options_overrides"] == nil, "audio keeps server selector")
        let directAudio = try JSONSerialization.jsonObject(with: DownloadRequest.body(url: "https://example.com/movie.webm", quality: "480", audioOnly: true)) as! [String: Any]
        check(directAudio["format"] as? String == "mp3", "direct audio still converts to MP3")
        let raw = #"{"done":[{"id":"a","title":"Title","url":"https://youtu.be/a","status":"finished","percent":100,"size":123,"filename":"a.mp4"}],"queue":[],"pending":[]}"#.data(using: .utf8)!
        let history = try JSONDecoder().decode(History.self, from: raw)
        let mixedOverrides=Data(#"{"id":"x","title":"X","url":"https://example.com/x","status":"error","ytdl_options_overrides":{"proxy":"http://proxy.example:7890","http_headers":{"X-Test":"fixture"},"retries":3}}"#.utf8)
        let mixed=try JSONDecoder().decode(DownloadItem.self,from:mixedOverrides)
        check(mixed.ytdlOptionsOverrides?["proxy"]=="http://proxy.example:7890","unrelated nested overrides do not break whole history")
        let item = history.done.first!
        check(item.id == item.url, "UI identity must use URL rather than extractor id")
        for action in DownloadAction.allCases {
            let request = try ActionRequest(action, item: item)
            let body = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
            if action == .retry {
                check(body["id"] as? String == item.url, "retry identifies item by URL")
                check(request.route == "retry", "retry endpoint")
            } else {
                check(body["ids"] as? [String] == [item.url], "actions identify items by URL")
            }
            if action == .clear || action == .cancel {
                check(body["delete_files"] as? Bool == false, "actions must preserve files")
                check(body["where"] as? String == (action == .clear ? "done" : "queue"), "correct queue")
            }
        }
        check(history.done.first!.isComplete, "complete status")
        check(history.done.first!.size == 123, "integer bytes")
        func fixture(_ fields: String) throws -> DownloadItem {
            try JSONDecoder().decode(DownloadItem.self, from: Data(("{\"id\":\"test\",\"title\":\"Test\",\"url\":\"https://example.com/test\"," + fields + "}").utf8))
        }
        let queuedAudio = try fixture(#""status":"downloading","download_type":"audio","format":"mp3""#)
        let legacyAudio = try fixture(#""status":"finished","filename":"song.MP3""#)
        let failedAudio = try fixture(#""status":"error","format":"mp3""#)
        let explicitVideo = try fixture(#""status":"finished","download_type":"video","filename":"odd.mp3""#)
        check(queuedAudio.isAudio && legacyAudio.isAudio && failedAudio.isAudio, "audio recognized before filename and in legacy history")
        check(!explicitVideo.isAudio && !item.isAudio, "explicit video type wins over filename")
        check(TaskList.visible(active: [queuedAudio], pending: [], history: [item], audioOnly: true, filter: "全部").count == 1, "audio tab excludes video history")
        check(TaskList.visible(active: [queuedAudio], pending: [], history: [item], audioOnly: false, filter: "进行中").isEmpty, "status and media filters combine")
        check(TaskList.visible(active: [], pending: [], history: [failedAudio], audioOnly: true, filter: "已完成").isEmpty, "failed is not completed")
        check(TaskList.visible(active: [queuedAudio], pending: [], history: [item], audioOnly: nil, filter: "全部").count == 2, "all media independent of submit mode")
        check(TaskList.visible(active: [queuedAudio], pending: [], history: [failedAudio, item], audioOnly: nil, filter: "失败").count == 1, "failed filter")
        let removal = try JSONSerialization.jsonObject(with: HistoryRemoval.body(items: [queuedAudio, legacyAudio, failedAudio, item])) as! [String: Any]
        check(Set(removal["ids"] as! [String]) == Set([legacyAudio.url, item.url]), "only terminal selected records, deduplicated")
        check(removal["where"] as? String == "done" && removal["delete_files"] as? Bool == false, "bulk history removal preserves files and queue")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("valid.mp4"))
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data().write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        check(SafeDownloadPath.resolve(filename: "valid.mp4", folder: nil, root: root) != nil, "valid file")
        let nested = root.appendingPathComponent("custom/playlist")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("track.mp4"))
        check(SafeDownloadPath.resolve(filename: "playlist/track.mp4", folder: "custom", root: root)?.path == nested.appendingPathComponent("track.mp4").path, "filename is relative to selected folder")
        check(SafeDownloadPath.resolve(filename: "../" + outside.lastPathComponent, folder: nil, root: root) == nil, "traversal")
        check(SafeDownloadPath.resolve(filename: "/etc/passwd", folder: nil, root: root) == nil, "absolute path")
        check(SafeDownloadPath.resolve(filename: "escape", folder: nil, root: root) == nil, "symlink escape")
        check(SafeDownloadPath.resolve(filename: "missing.mp4", folder: nil, root: root) == nil, "missing file")
        let destination = root.appendingPathComponent("export-target")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("valid.mp4")
        try Data("original-video".utf8).write(to: source)
        try Data("existing-user-file".utf8).write(to: destination.appendingPathComponent("valid.mp4"))
        let copied = try ExportFiles.copy(source, into: destination)
        check(copied.lastPathComponent == "valid (1).mp4", "export must not overwrite existing file")
        check(try! Data(contentsOf: destination.appendingPathComponent("valid.mp4")) == Data("existing-user-file".utf8), "existing file preserved")
        check(try! Data(contentsOf: copied) == Data(contentsOf: source), "copy bytes identical")
        check(FileManager.default.fileExists(atPath: source.path), "staging source retained")
        check(try! ExportFiles.copy(source, into: root) == source, "same directory avoids duplicate copy")
        check((try? ExportFiles.copy(source, into: root.appendingPathComponent("missing-directory"))) == nil, "missing destination does not silently fall back")
        check((try? APIResult.validate(Data(#"{"status":"error","msg":"failed"}"#.utf8))) == nil, "API errors")
        try APIResult.validate(Data(#"{"status":"ok"}"#.utf8))
        if CommandLine.arguments.contains("--live") {
            let live = try await Backend().history()
            print("Live history decoded: \(live.done.count) done, \(live.queue.count) active, \(live.pending.count) pending")
        }
        print("PASS: link, history, path, API result tests")
    }
}
