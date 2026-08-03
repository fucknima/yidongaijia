import MobileVLCKit
import SwiftUI
import UIKit

struct VLCPlayerView: UIViewRepresentable {
    // PlayerScreen/HistoryView already observe the model. Observing it here
    // causes every replay progress tick to call updateUIView and reconfigure
    // the VLC player.
    let model: PlayerViewModel
    let role: PlayerViewRole

    init(model: PlayerViewModel, role: PlayerViewRole = .inline) {
        self.model = model
        self.role = role
    }

    final class Coordinator {
        weak var model: PlayerViewModel?
        let role: PlayerViewRole

        init(model: PlayerViewModel, role: PlayerViewRole) {
            self.model = model
            self.role = role
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, role: role)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        model.attach(to: view, role: role)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        model.attach(to: uiView, role: role)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.model?.detach(from: uiView, role: coordinator.role)
    }
}
