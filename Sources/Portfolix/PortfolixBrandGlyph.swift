import AppKit
import SwiftUI

struct PortfolixBrandGlyph: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(PortfolixTheme.brandLogoInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "PortfolixBrandGlyph", withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
