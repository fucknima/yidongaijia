import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct RecordingDownloadAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var downloadedBytes: Int64
        var status: String
    }

    var fileName: String
}

@MainActor
final class RecordingDownloadManager: NSObject, ObservableObject {
    @Published private(set) var recordingID: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var stateText = ""
    @Published private(set) var savedURL: URL?

    var isDownloading: Bool { recordingID != nil }

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var activity: Any?
    private var expectedDuration: TimeInterval = 1
    private var startedAt = Date()
    private var timer: Timer?
    private var completion: ((Result<URL, Error>) -> Void)?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.aijiadirect.recording-download")
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func start(url: URL, recording: AijiaRecording, completion: @escaping (Result<URL, Error>) -> Void) {
        cancel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "摄像头录像-\(formatter.string(from: recording.startDate)).flv"
        recordingID = recording.id
        progress = 0
        downloadedBytes = 0
        stateText = "准备下载"
        savedURL = nil
        expectedDuration = max(1, TimeInterval(recording.endTime - recording.startTime))
        startedAt = Date()
        self.completion = completion
        startActivity(fileName: fileName)

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        task = session.downloadTask(with: request)
        task?.taskDescription = fileName
        task?.resume()
        stateText = "正在下载"
        updateActivity()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateEstimatedProgress() }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        timer?.invalidate()
        timer = nil
        if recordingID != nil { endActivity(status: "已取消", progress: progress) }
        recordingID = nil
        stateText = ""
        completion = nil
    }

    private func updateEstimatedProgress() {
        guard isDownloading else { return }
        // Card streams are commonly chunked and omit Content-Length. In that
        // case the recording duration is a better progress denominator.
        if task?.countOfBytesExpectedToReceive ?? -1 <= 0 {
            progress = min(0.98, Date().timeIntervalSince(startedAt) / expectedDuration)
            updateActivity()
        }
    }

    nonisolated private static func destination(for fileName: String) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = documents.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let stem = base.deletingPathExtension().lastPathComponent
        return documents.appendingPathComponent("\(stem)-\(Int(Date().timeIntervalSince1970)).flv")
    }

    private func finish(_ result: Result<URL, Error>) {
        timer?.invalidate()
        timer = nil
        task = nil
        switch result {
        case let .success(url):
            progress = 1
            savedURL = url
            stateText = "下载完成"
            endActivity(status: "下载完成", progress: 1)
        case let .failure(error):
            stateText = "下载失败：\(error.localizedDescription)"
            endActivity(status: "下载失败", progress: progress)
        }
        recordingID = nil
        let handler = completion
        completion = nil
        handler?(result)
    }

    @available(iOS 16.1, *)
    private var typedActivity: Activity<RecordingDownloadAttributes>? {
        activity as? Activity<RecordingDownloadAttributes>
    }

    private func startActivity(fileName: String) {
        guard #available(iOS 16.1, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingDownloadAttributes(fileName: fileName)
        let content = RecordingDownloadAttributes.ContentState(progress: 0, downloadedBytes: 0, status: "准备下载")
        activity = try? Activity.request(attributes: attributes, contentState: content, pushType: nil)
    }

    private func updateActivity() {
        guard #available(iOS 16.1, *), let activity = typedActivity else { return }
        let content = RecordingDownloadAttributes.ContentState(
            progress: progress,
            downloadedBytes: downloadedBytes,
            status: stateText
        )
        Task { await activity.update(using: content) }
    }

    private func endActivity(status: String, progress: Double) {
        guard #available(iOS 16.1, *), let activity = typedActivity else { return }
        let content = RecordingDownloadAttributes.ContentState(
            progress: progress,
            downloadedBytes: downloadedBytes,
            status: status
        )
        Task { await activity.end(using: content, dismissalPolicy: .default) }
        self.activity = nil
    }
}

extension RecordingDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor [weak self] in
            guard let self, downloadTask === self.task else { return }
            self.downloadedBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                self.progress = min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
            self.updateActivity()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let name = downloadTask.taskDescription ?? "摄像头录像.flv"
            let target = try Self.destination(for: name)
            try FileManager.default.moveItem(at: location, to: target)
            Task { @MainActor [weak self] in self?.finish(.success(target)) }
        } catch {
            Task { @MainActor [weak self] in self?.finish(.failure(error)) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        Task { @MainActor [weak self] in
            guard task === self?.task else { return }
            self?.finish(.failure(error))
        }
    }
}
