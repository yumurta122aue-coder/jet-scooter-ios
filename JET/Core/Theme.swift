import SwiftUI

enum Theme {
    static let bg        = Color(hex: 0x080B08)
    static let surface   = Color(hex: 0x121712)
    static let surfaceHi = Color(hex: 0x1C231C)
    static let stroke    = Color(hex: 0x2A332A)
    static let lime      = Color(hex: 0x7CFC00)
    static let limeSoft  = Color(hex: 0x7CFC00).opacity(0.14)
    static let text      = Color(hex: 0xF2F5F2)
    static let textDim   = Color(hex: 0x8B968B)
    static let danger    = Color(hex: 0xFF5252)
    static let amber     = Color(hex: 0xFFB300)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension Double {
    var money: String { String(format: "$%.2f", self) }
    var oneDecimal: String { String(format: "%.1f", self) }
}

extension TimeInterval {
    var clock: String {
        let total = Int(self)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? Theme.lime : Theme.stroke)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}
