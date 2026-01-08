import SwiftUI

enum Typography {
    // TODO: сюда вставим реальный PostScript name после проверки в консоли.
    // Пока пусть будет имя-заглушка; если шрифт не найден, приложение НЕ упадёт, просто будет system font.
    static let baaquaPostScriptName: String = "BaAQUA-C"
    
    static func font(_ choice: AppSettings.FontChoice, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch choice {
        case .system:
            return .system(size: size, weight: weight)
        case .baaqua:
            return .custom(baaquaPostScriptName, size: size).weight(weight)
        }
    }
}

extension View {
    func appFontDefault(_ choice: AppSettings.FontChoice) -> some View {
        self.font(Typography.font(choice, size: 17))
    }
}
