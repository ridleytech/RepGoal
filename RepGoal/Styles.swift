//
//  Styles.swift (v14)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppStyle {
    static let sectionHeaderBottomSpacing: CGFloat = 8

    @ViewBuilder
    static func header(_ title: String) -> some View {
        Text(title).padding(.bottom, sectionHeaderBottomSpacing)
    }

    /// Decrease navigation titles by 5pt (both large and inline)
    static func applyNavigationTitleSizing() {
        #if canImport(UIKit)
        let large = UIFont.preferredFont(forTextStyle: .largeTitle)
        let inlineBase = UIFont.preferredFont(forTextStyle: .headline)
        let largeFont = UIFont.systemFont(ofSize: max(large.pointSize - 5.0, 16.0), weight: .bold)
        let inlineFont = UIFont.systemFont(ofSize: max(inlineBase.pointSize - 5.0, 10.0), weight: .semibold)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: largeFont]
        appearance.titleTextAttributes = [.font: inlineFont]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        }
        #endif
    }
}
