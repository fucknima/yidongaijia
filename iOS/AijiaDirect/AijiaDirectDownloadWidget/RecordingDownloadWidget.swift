import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingDownloadAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var downloadedBytes: Int64
        var status: String
    }

    var fileName: String
}

@main
struct RecordingDownloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingDownloadWidget()
    }
}

struct RecordingDownloadWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingDownloadAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(context.state.status, systemImage: "video.fill")
                    .font(.headline)
                ProgressView(value: context.state.progress)
                Text(context.attributes.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "arrow.down")
                    .foregroundStyle(.blue)
            }
        }
    }
}
