import SwiftUI

enum Theme {
    static let bgDark = Color(red: 0.102, green: 0.102, blue: 0.180)
    static let bgCard = Color(red: 0.145, green: 0.145, blue: 0.259)
    static let accent = Color(red: 0.914, green: 0.118, blue: 0.388)
    static let blue   = Color(red: 0.129, green: 0.588, blue: 0.953)
    static let green  = Color(red: 0.298, green: 0.686, blue: 0.314)
    static let orange = Color(red: 1.000, green: 0.443, blue: 0.224)
    static let amber  = Color(red: 1.000, green: 0.596, blue: 0.000)
    static let border = Color(red: 0.227, green: 0.227, blue: 0.361)
    static let textSecondary = Color(red: 0.690, green: 0.690, blue: 0.753)

    // Severity tokens — single source of truth for finding visuals.
    // ReportSeverity.color routes here so badges, donuts, bars and card
    // borders stay consistent across the Security Lab.
    static let sevCritical = Color(red: 0.86, green: 0.18, blue: 0.32)
    static let sevHigh     = orange
    static let sevMedium   = amber
    static let sevLow      = blue
    static let sevInfo     = textSecondary

    static let gradient = LinearGradient(
        colors: [accent, blue],
        startPoint: .leading,
        endPoint: .trailing
    )
}

enum OutputStatus {
    case none, success, error, info
}
