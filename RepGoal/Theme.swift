//
//  Theme.swift (v13)
import SwiftUI

struct ThemePalette {
    let onTint: Color
    let offTint: Color
    let text: Color
    let background: Color
}

enum ThemeOption: Int, CaseIterable, Identifiable {
    case system = 0
    case ocean, sunset, forest, graphite, candy, highContrast
    case midnight, neonDark, amberDark, aquaDark, crimsonDark
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .system: return "System"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        case .graphite: return "Graphite"
        case .candy: return "Candy"
        case .highContrast: return "High Contrast"
        case .midnight: return "Midnight (Dark)"
        case .neonDark: return "Neon (Dark)"
        case .amberDark: return "Amber (Dark)"
        case .aquaDark: return "Aqua (Dark)"
        case .crimsonDark: return "Crimson (Dark)"
        }
    }
    var isDark: Bool {
        switch self {
        case .midnight, .neonDark, .amberDark, .aquaDark, .crimsonDark: return true
        default: return false
        }
    }
    var palette: ThemePalette {
        switch self {
        case .system:
            return ThemePalette(onTint: .accentColor, offTint: .secondary, text: .primary, background: Color(.systemBackground))
        case .ocean:
            return ThemePalette(onTint: Color(hex: 0x0EA5E9), offTint: Color(hex: 0x94A3B8), text: Color(hex: 0x0B132B), background: Color(hex: 0xE6F4F9))
        case .sunset:
            return ThemePalette(onTint: Color(hex: 0xF97316), offTint: Color(hex: 0xFBBF24), text: Color(hex: 0x1F2937), background: Color(hex: 0xFFF7ED))
        case .forest:
            return ThemePalette(onTint: Color(hex: 0x16A34A), offTint: Color(hex: 0x9CA3AF), text: Color(hex: 0x0B3D2E), background: Color(hex: 0xECFDF5))
        case .graphite:
            return ThemePalette(onTint: Color(hex: 0x6B7280), offTint: Color(hex: 0x9CA3AF), text: .primary, background: Color(hex: 0xF3F4F6))
        case .candy:
            return ThemePalette(onTint: Color(hex: 0xD946EF), offTint: Color(hex: 0xF9A8D4), text: Color(hex: 0x3B0764), background: Color(hex: 0xFFF1F2))
        case .highContrast:
            return ThemePalette(onTint: .black, offTint: .gray, text: .black, background: .white)
        case .midnight:
            return ThemePalette(onTint: Color(hex: 0x60A5FA), offTint: .white.opacity(0.5), text: .white, background: Color(hex: 0x0F1115))
        case .neonDark:
            return ThemePalette(onTint: Color(hex: 0x22D3EE), offTint: .white.opacity(0.5), text: .white, background: Color(hex: 0x101418))
        case .amberDark:
            return ThemePalette(onTint: Color(hex: 0xF59E0B), offTint: .white.opacity(0.5), text: .white, background: Color(hex: 0x121214))
        case .aquaDark:
            return ThemePalette(onTint: Color(hex: 0x34D399), offTint: .white.opacity(0.5), text: .white, background: Color(hex: 0x0E1412))
        case .crimsonDark:
            return ThemePalette(onTint: Color(hex: 0xF43F5E), offTint: .white.opacity(0.5), text: .white, background: Color(hex: 0x141014))
        }
    }
    var swatch: [Color] { [palette.onTint, palette.offTint, palette.text, palette.background] }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: alpha)
    }
}

enum ThemeKit {
    static func palette(_ settings: AppSettings?) -> ThemePalette {
        guard let s = settings else { return ThemeOption.system.palette }
        let opt = ThemeOption(rawValue: s.themeRaw) ?? .system
        return opt.palette
    }
    static func isDark(_ settings: AppSettings?) -> Bool {
        guard let s = settings else { return false }
        return (ThemeOption(rawValue: s.themeRaw) ?? .system).isDark
    }
}

struct Themed: ViewModifier {
    let palette: ThemePalette
    let isDark: Bool
    func body(content: Content) -> some View {
        content
            .tint(palette.onTint)
            .foregroundStyle(palette.text)
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .preferredColorScheme(isDark ? .dark : .light)
    }
}
extension View {
    func themed(palette: ThemePalette, isDark: Bool) -> some View { self.modifier(Themed(palette: palette, isDark: isDark)) }
}

struct ThemedProminentButtonStyle: ButtonStyle {
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.onTint)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
