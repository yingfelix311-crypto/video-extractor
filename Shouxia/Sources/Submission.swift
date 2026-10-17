import Foundation

enum SubmissionState: String, Codable, Sendable {
    case parsing, cancelling, uncertain, failed
    var label: String {
        switch self {
        case .parsing: "正在读取视频信息"
        case .cancelling: "正在停止解析并核对任务"
        case .uncertain: "等待核对后台结果"
        case .failed: "未能创建下载任务"
        }
    }
}

struct SubmissionIntent: Codable, Identifiable, Sendable {
    let id: String
    let link: ResolvedLink
    let quality: String
    let audioOnly: Bool
    let options: DownloadOptions
    let destination: String
    let createdAt: Date
    var state: SubmissionState
    var error: String?
    var summary: String { audioOnly ? "音频 · MP3" : "视频 · \(quality == "best" ? "最佳画质" : "不高于 " + quality + "p") · \(options.videoFormat == "mp4" ? "MP4 源格式" : "原始最佳格式")" }
}
