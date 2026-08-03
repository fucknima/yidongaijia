import MobileVLCKit
import SwiftUI
import UIKit

struct VLCPlayerView: UIViewRepresentable {
    // PlayerScreen/HistoryView already observe the model. Observing it here
    // would cause every replay progress tick to rebuild the representable.
    let model: PlayerViewModel

    final class Coordinator {
        weak var model: PlayerViewModel?

        init(model: PlayerViewModel) {
            self.model = model
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> UIView {
        let view = VLCVideoView()
        view.backgroundColor = .black
        view.onLayout = { [weak model] view in
            model?.refreshDrawable(for: view)
        }
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        model.attach(to: uiView)
        model.refreshDrawable(for: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        (uiView as? VLCVideoView)?.onLayout = nil
        coordinator.model?.detach(from: uiView)
    }
}

private final class VLCVideoView: UIView {
    var onLayout: ((UIView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
