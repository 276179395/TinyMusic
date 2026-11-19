import SwiftUI
import UIKit

/// 全屏横向右滑返回。把 pan 挂到 window 上，避免和 NavigationStack 的
/// 系统边缘返回手势/歌词 ScrollView 抢触摸；底部的播放控制区不参与。
struct WindowSwipeBack: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> WindowSwipeBackView {
        let view = WindowSwipeBackView()
        view.action = action
        return view
    }

    func updateUIView(_ uiView: WindowSwipeBackView, context: Context) {
        uiView.action = action
    }
}

final class WindowSwipeBackView: UIView, UIGestureRecognizerDelegate {
    var action: (() -> Void)?
    private var pan: UIPanGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, pan == nil else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        self.pan = pan
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, let pan {
            pan.view?.removeGestureRecognizer(pan)
            self.pan = nil
        }
    }

    @objc private func handle(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view else { return }
        let translation = gesture.translation(in: view)
        if translation.x > 80, abs(translation.y) < 110 {
            action?()
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) * 1.4 else { return false }
        let location = pan.location(in: view)
        // 底部 190pt 是进度条和播放控制，避免横向拖动被当成返回。
        return location.y < view.bounds.height - 190
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
