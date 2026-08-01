//
//  ShakeGesture.swift
//  Noticing that the phone was shaken.
//
//  SwiftUI has no shake gesture, so this goes the usual route: UIKit already
//  delivers motion events to the responder chain, and a window that forwards
//  them as a notification turns that into something a view can observe.
//
//  A shake is undiscoverable and unavailable to anyone who can't shake a phone,
//  so wherever this is used there is always a visible control that does the same
//  thing. It's a flourish on top of a button, never the only way through.
//

import SwiftUI
import UIKit

extension UIDevice {
    static let didShakeNotification = Notification.Name("NinetyNine.deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: UIDevice.didShakeNotification, object: nil)
    }
}

private struct ShakeDetector: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: UIDevice.didShakeNotification)
        ) { _ in
            guard isEnabled else { return }
            action()
        }
    }
}

extension View {
    /// Run `action` when the device is shaken.
    ///
    /// `isEnabled` matters: the notification is global, so every listener hears
    /// every shake. Gating at the view keeps a shake meant for one screen from
    /// firing on another that happens to be in the hierarchy.
    func onShake(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(isEnabled: isEnabled, action: action))
    }
}
