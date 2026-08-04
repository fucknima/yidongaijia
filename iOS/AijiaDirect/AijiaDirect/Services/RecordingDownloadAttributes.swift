import ActivityKit

@available(iOS 16.1, *)
struct RecordingDownloadAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var downloadedBytes: Int64
        var status: String
        var speedText: String
    }

    var fileName: String
}
