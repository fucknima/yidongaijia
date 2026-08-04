import MobileVLCKit
import SwiftUI
import UIKit

enum VLCPlayerSurfaceRole {
    case inline
    case fullscreen
}

struct VLCPlayerView: UIViewRepresentable {
    // PlayerScreen/HistoryView already observe the model. Observing it here
    // would cause every replay progress tick to rebuild the representable.
    let model: PlayerViewModel
    let role: VLCPlayerSurfaceRole

    init(model: PlayerViewModel, role: VLCPlayerSurfaceRole = .inline) {
        self.model = model
        self.role = role
    }

    final class Coordinator {
        weak var model: PlayerViewModel?
        let role: VLCPlayerSurfaceRole

        init(model: PlayerViewModel, role: VLCPlayerSurfaceRole) {
            self.model = model
            self.role = role
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, role: role)
    }

    func makeUIView(context: Context) -> UIView {
        let hostView = VLCPlayerHostView()
        hostView.backgroundColor = .black
        hostView.model = model
        model.mountPlayerSurface(in: hostView, role: role)
        return hostView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let hostView = uiView as? VLCPlayerHostView else { return }
        hostView.model = model
        model.mountPlayerSurface(in: hostView, role: role)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        guard let hostView = uiView as? VLCPlayerHostView else { return }
        coordinator.model?.unmountPlayerSurface(from: hostView, role: coordinator.role)
        hostView.model = nil
    }
}

private final class VLCPlayerHostView: UIView {
    weak var model: PlayerViewModel?

    override func layoutSubviews() {
        super.layoutSubviews()
        model?.layoutPlayerSurface(in: self)
    }
}
