import SwiftUI
import UIKit

enum Typography {
    private static func resolveBaaqua(size: CGFloat) -> UIFont? {
        // Direct tries first (fast)
        let direct: [String] = [
            "BaAQUA_C",
            "BaAQUA-C",
            "BaAQUA C",
            "BaAQUA-C Regular",
            "BaAQUA_C Regular"
        ]
        for name in direct {
            if let f = UIFont(name: name, size: size) { return f }
        }
        
        // Fallback: scan installed fonts and match by substring
        for family in UIFont.familyNames {
            for name in UIFont.fontNames(forFamilyName: family) {
                if name.localizedCaseInsensitiveContains("BaAQUA") {
                    if let f = UIFont(name: name, size: size) { return f }
                }
            }
        }
        return nil
    }
    
    static func font(_ choice: AppSettings.FontChoice, size: CGFloat, bold: Bool) -> Font {
        switch choice {
        case .system:
            return .system(size: size, weight: bold ? .bold : .regular)
            
        case .baaqua:
            guard let base = resolveBaaqua(size: size) else {
                return .system(size: size, weight: bold ? .bold : .regular)
            }
            
            guard bold else { return Font(base) }
            
            // 1) Try symbolic bold trait
            if let desc = base.fontDescriptor.withSymbolicTraits([.traitBold]) {
                let boldFont = UIFont(descriptor: desc, size: size)
                if boldFont.fontName != base.fontName {
                    return Font(boldFont)
                }
            }
            
            // 2) Try weight trait (often works even when .traitBold fails)
            let traits: [UIFontDescriptor.TraitKey: Any] = [
                .weight: UIFont.Weight.bold
            ]
            let weightedDesc = base.fontDescriptor.addingAttributes([.traits: traits])
            let weightedFont = UIFont(descriptor: weightedDesc, size: size)
            if weightedFont.fontName != base.fontName {
                return Font(weightedFont)
            }
            
            // 3) Fallback: keep UI bold behavior even if font has no bold face
            return .system(size: size, weight: .bold)
        }
    }
}

extension View {
    func appFontDefault(_ choice: AppSettings.FontChoice, bold: Bool = false) -> some View {
        self.font(Typography.font(choice, size: 17, bold: bold))
    }
}
