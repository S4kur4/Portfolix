import SwiftUI

struct PortfolixAnalysisGlyph: View {
    var body: some View {
        Image(systemName: AIReportComposerAction.analyze.symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 22, height: 22)
            // Balance the symbol's heavier lower loops without changing the button's layout.
            .offset(y: -0.25)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
