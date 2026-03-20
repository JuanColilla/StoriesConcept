import SnapshotTesting
import SwiftUI
import UIKit

// MARK: - View Hosting

/// Wraps a SwiftUI view in a UIHostingController sized for iPhone 15 Pro (393×852).
func hostView<V: View>(
    _ view: V,
    colorScheme: ColorScheme = .light,
    width: CGFloat = 393,
    height: CGFloat = 852
) -> UIViewController {
    let themed = view.environment(\.colorScheme, colorScheme)
    let vc = UIHostingController(rootView: AnyView(themed))
    vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    vc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    vc.view.layoutIfNeeded()
    return vc
}

/// Wraps a SwiftUI view in a compact container (e.g., for row/component snapshots).
func hostComponent<V: View>(
    _ view: V,
    colorScheme: ColorScheme = .light,
    width: CGFloat = 393,
    height: CGFloat? = nil
) -> UIViewController {
    let themed = view.environment(\.colorScheme, colorScheme)
    let vc = UIHostingController(rootView: AnyView(themed))
    vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

    // Let the view size itself vertically if no height specified
    let size: CGSize
    if let height {
        size = CGSize(width: width, height: height)
    } else {
        let fitting = vc.view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        size = CGSize(width: width, height: max(fitting.height, 80))
    }

    vc.view.frame = CGRect(origin: .zero, size: size)
    vc.view.layoutIfNeeded()
    return vc
}

// MARK: - Naming

enum AppearanceMode: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}
