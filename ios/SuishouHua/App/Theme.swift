import Foundation
import SwiftUI
import UIKit

/// 应用主题色：暖白背景、石墨文字、蓝色主色。
enum Theme {
    static let blue = Color(hex: "#3577F2")!
    static let orange = Color(hex: "#F28C28")!
    static let green = Color(hex: "#4CAF50")!
    static let pink = Color(hex: "#E91E63")!
    static let purple = Color(hex: "#9C27B0")!

    static let background = Color(hex: "#F7F5F1")!   // 暖白
    static let canvasWhite = Color.white
    static let ink = Color(hex: "#2B2B2E")!          // 石墨
    static let inkSecondary = Color(hex: "#8A8A8E")!
    static let strokePalette: [String] = ["#3577F2", "#F28C28", "#4CAF50", "#E91E63", "#9C27B0"]
}

extension Color {
    init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
