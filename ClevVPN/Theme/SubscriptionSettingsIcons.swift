import CoreGraphics

/// SF Symbol names and sizes for `SubscriptionSettingsCard` (macOS / iOS).
/// Windows (`SubscriptionSettingsIcons.cs`) and Android (`SubscriptionSettingsIcons.kt`) mirror this file.
enum SubscriptionSettingsIcons {
    enum Symbol {
        static let titleAvatar = "person.circle"
        static let statsCalendar = "calendar"
        static let refresh = "arrow.clockwise"
        static let signOut = "rectangle.portrait.and.arrow.right"
        static let buyInBot = "cart.fill"
        static let support = "headphones"
    }

    enum Size {
        static let titleAvatar: CGFloat = 22
        static let statsCalendar: CGFloat = 12
        static let action: CGFloat = 14
    }
}
