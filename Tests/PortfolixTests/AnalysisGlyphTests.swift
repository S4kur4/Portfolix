import AppKit
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Static Apple Intelligence analysis button") @MainActor
struct AnalysisGlyphTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func glyphIsOpticallyCenteredAtDisplayScales(scheme: ColorScheme) throws {
        for scale: CGFloat in [1, 2, 3, 4] {
            let renderer = ImageRenderer(content: PortfolixAnalysisGlyph().foregroundStyle(PortfolixTheme.primaryButtonText)
                .frame(width: 32, height: 32).background(PortfolixTheme.primaryButtonTint, in: Circle())
                .padding(4).background(PortfolixTheme.panel).environment(\.colorScheme, scheme))
            renderer.scale = scale
            let metrics = try inkMetrics(try #require(renderer.cgImage), scale: scale)
            #expect(abs(metrics.center.x - 20) < 0.3)
            #expect(abs(metrics.center.y - 20) < 0.3)
            #expect(abs(metrics.bounds.midX - 20) <= 0.5)
            #expect(abs(metrics.bounds.midY - 20) <= 0.5)
        }
    }

    private func inkMetrics(_ image: CGImage, scale: CGFloat) throws -> (bounds: CGRect, center: CGPoint) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var weight = 0.0, sumX = 0.0, sumY = 0.0
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                guard hypot(CGFloat(x) + 0.5 - 20 * scale, CGFloat(y) + 0.5 - 20 * scale) < 14 * scale,
                      let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let amount = max(0, 1 - color.blueComponent)
                weight += amount
                sumX += (Double(x) + 0.5) * amount
                sumY += (Double(y) + 0.5) * amount
                if amount > 0.25 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        #expect(weight > 1 && maxX >= minX && maxY >= minY)
        return (CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                       width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale),
                CGPoint(x: sumX / weight / scale, y: sumY / weight / scale))
    }

    @Test
    func analysisUsesTheNativeAppleIntelligenceSymbol() throws {
        #expect(AIReportComposerAction.analyze.symbol == "apple.intelligence")
        #expect(AIReportComposerAction.send.symbol == "arrow.up")
        #expect(AIReportComposerAction.stop.symbol == "stop.fill")
        _ = try #require(NSImage(systemSymbolName: AIReportComposerAction.analyze.symbol, accessibilityDescription: nil))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func buttonKeepsItsSizeAcrossModesAndEnabledStates(scheme: ColorScheme) {
        for mode in AIReportComposerAction.allCases {
            for isEnabled in [true, false] {
                let host = NSHostingView(rootView: AIReportComposerActionButton(
                    mode: mode, title: "Test", isEnabled: isEnabled, action: {})
                    .environment(\.colorScheme, scheme))
                #expect(host.fittingSize == CGSize(width: 32, height: 32))
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func staticGlyphRendersWithoutChangingBetweenFrames(scheme: ColorScheme) throws {
        let content = PortfolixAnalysisGlyph()
            .foregroundStyle(PortfolixTheme.primaryButtonText)
            .frame(width: 32, height: 32)
            .background(PortfolixTheme.primaryButtonTint, in: Circle())
            .padding(4)
            .background(PortfolixTheme.panel)
            .environment(\.colorScheme, scheme)
        let first = ImageRenderer(content: content)
        first.scale = 3
        let second = ImageRenderer(content: content)
        second.scale = 3
        let image = try #require(first.cgImage)
        let next = try #require(second.cgImage)
        #expect(image.width == 120 && image.height == 120)
        let pixels = try #require(image.dataProvider?.data) as Data
        let nextPixels = try #require(next.dataProvider?.data) as Data
        #expect(pixels == nextPixels)
        if let directory = ProcessInfo.processInfo.environment["PORTFOLIX_ANALYSIS_GLYPH_PREVIEW_DIRECTORY"] {
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(scheme == .dark
                ? "analysis-intelligence-dark.png" : "analysis-intelligence-light.png"))
        }
    }
}
