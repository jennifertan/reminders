import SwiftUI
import UIKit

// Ringlet's ink green and amber look. The colors live in the asset catalog so each has a light and
// dark variant, and Xcode generates `Color.canvas` (the soft green-grey page behind lists and forms),
// `Color.heading` (deep ink green for titles) and `Color.highlight` (amber, for the add button and
// alarm actions) from them. The accent (green) is AccentColor, so buttons, toggles and links pick it up.

extension View {
    /// Swaps the stock grey list and form background for the Ringlet canvas.
    func ringletBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.canvas)
    }
}

enum Theme {
    /// Styles the navigation and tab bars, which SwiftUI can't theme app-wide on iOS 17.
    @MainActor
    static func applyBarAppearance() {
        let canvas = UIColor(named: "Canvas") ?? .systemGroupedBackground
        let heading = UIColor(named: "Heading") ?? .label

        let scrolledNav = UINavigationBarAppearance()
        scrolledNav.configureWithDefaultBackground()
        scrolledNav.backgroundColor = canvas.withAlphaComponent(0.85)
        let edgeNav = UINavigationBarAppearance()
        edgeNav.configureWithTransparentBackground()
        for appearance in [scrolledNav, edgeNav] {
            appearance.titleTextAttributes = [.foregroundColor: heading]
            appearance.largeTitleTextAttributes = [.foregroundColor: heading]
        }
        UINavigationBar.appearance().standardAppearance = scrolledNav
        UINavigationBar.appearance().compactAppearance = scrolledNav
        UINavigationBar.appearance().scrollEdgeAppearance = edgeNav

        let tabBar = UITabBarAppearance()
        tabBar.configureWithDefaultBackground()
        tabBar.backgroundColor = canvas.withAlphaComponent(0.85)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }
}

/// The Light/Dark choice in Settings. System follows the phone's own setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Set on the windows rather than with preferredColorScheme, which doesn't reliably switch back to System
    /// and leaves sheets and the UIKit bars behind.
    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = interfaceStyle }
        }
    }
}
