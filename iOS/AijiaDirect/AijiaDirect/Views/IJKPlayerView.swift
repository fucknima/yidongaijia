import IJKMediaFramework
import SwiftUI
import UIKit

enum IJKPlayerSurfaceRole {
    case inline
    case fullscreen
}

struct IJKPlayerView: UIViewRepresentable {
    // PlayerScreen/HistoryView already observe the model. Observing it here
    // would cause every replay progress tick to rebuild the representable.
    let model: PlayerViewModel
    let role: IJKPlayerSurfaceRole

    init(model: PlayerViewModel, role: IJKPlayerSurfaceRole = .inline) {
        self.model = model
        self.role = role
    }

    final class Coordinator {
        weak var model: PlayerViewModel?
        let role: IJKPlayerSurfaceRole

        init(model: PlayerViewModel, role: IJKPlayerSurfaceRole) {
            self.model = model
            self.role = role
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, role: role)
    }

    func makeUIView(context: Context) -> UIView {
        let hostView = IJKPlayerHostView()
        hostView.backgroundColor = .black
        hostView.model = model
        model.mountPlayerSurface(in: hostView, role: role)
        return hostView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let hostView = uiView as? IJKPlayerHostView else { return }
        hostView.model = model
        model.mountPlayerSurface(in: hostView, role: role)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        guard let hostView = uiView as? IJKPlayerHostView else { return }
        coordinator.model?.unmountPlayerSurface(from: hostView, role: coordinator.role)
        hostView.model = nil
    }
}

private final class IJKPlayerHostView: UIView {
    weak var model: PlayerViewModel?

    override func layoutSubviews() {
        super.layoutSubviews()
        model?.layoutPlayerSurface(in: self)
    }
}
