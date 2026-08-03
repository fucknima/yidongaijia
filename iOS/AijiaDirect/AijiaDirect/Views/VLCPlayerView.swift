import MobileVLCKit
import SwiftUI
import UIKit

struct VLCPlayerView: UIViewRepresentable {
    // PlayerScreen/HistoryView already observe the model. Observing it here
    // causes every replay progress tick to call updateUIView and reconfigure
    // the VLC player.
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
        let view = UIView()
        view.backgroundColor = .black
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // attach(to:) is idempotent for the current drawable and repairs the
        // binding when SwiftUI reuses this view after fullscreen dismissal.
        model.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.model?.detach(from: uiView)
    }
}
