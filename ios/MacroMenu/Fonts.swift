import SwiftUI
import UIKit
import CoreText

extension AppFonts {
    /// Registers the bundled fonts and styles the navigation and tab bars. Call once at launch.
    @MainActor static func setUp() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let bar = UINavigationBar.appearance()
        if let font = UIFont(name: display, size: 34 * displayScale) { bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font)] }
        if let font = UIFont(name: display, size: 20 * displayScale) { bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)] }
        if let font = UIFont(name: "Roboto-Medium", size: 10) { UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .normal) }
    }
}
