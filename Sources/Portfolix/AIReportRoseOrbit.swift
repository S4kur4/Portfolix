import SwiftUI

struct AIReportRoseOrbit: View {
    let date: Date
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, canvasSize in
            RoseOrbitRenderer.render(
                context: &context,
                canvasSize: canvasSize,
                time: reduceMotion ? 0 : date.timeIntervalSinceReferenceDate,
                isDarkMode: colorScheme == .dark
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum RoseOrbitRenderer {
    private static let visualScale = 0.9
    private static let particleCount = 140
    private static let pathSteps = 480
    private static let trailSpan = 0.4
    private static let orbitDuration = 5.0
    private static let rotationDuration = 20.0
    private static let pulseDuration = 10.0
    private static let orbitRadius = 7.0
    private static let detailAmplitude = 2.7
    private static let petalCount = 7.0
    private static let curveScale = 4.0

    static func render(context: inout GraphicsContext, canvasSize: CGSize, time: TimeInterval, isDarkMode: Bool) {
        let side = min(canvasSize.width, canvasSize.height)
        guard side > 0 else { return }

        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let visualSide = side * visualScale
        let origin = CGPoint(x: center.x - visualSide / 2, y: center.y - visualSide / 2)
        let scale = visualSide / 100
        let detailScale = detailScale(at: time)
        let progress = normalized(time / orbitDuration)

        var orbitContext = context
        orbitContext.translateBy(x: center.x, y: center.y)
        orbitContext.rotate(by: .radians(-normalized(time / rotationDuration) * 2 * .pi))
        orbitContext.translateBy(x: -center.x, y: -center.y)

        let path = rosePath(detailScale: detailScale, origin: origin, scale: scale)
        orbitContext.stroke(
            path,
            with: .color(PortfolixTheme.violet.opacity(isDarkMode ? 0.16 : 0.22)),
            style: StrokeStyle(
                lineWidth: max(1, 5.2 * scale),
                lineCap: .round,
                lineJoin: .round
            )
        )

        for index in 0..<particleCount {
            drawParticle(
                index: index,
                progress: progress,
                detailScale: detailScale,
                origin: origin,
                scale: scale,
                context: &orbitContext,
                isDarkMode: isDarkMode
            )
        }
    }

    private static func rosePath(detailScale: Double, origin: CGPoint, scale: CGFloat) -> Path {
        var path = Path()
        for index in 0...pathSteps {
            let progress = Double(index) / Double(pathSteps)
            let point = canvasPoint(progress: progress, detailScale: detailScale, origin: origin, scale: scale)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private static func drawParticle(
        index: Int,
        progress: Double,
        detailScale: Double,
        origin: CGPoint,
        scale: CGFloat,
        context: inout GraphicsContext,
        isDarkMode: Bool
    ) {
        let tailOffset = Double(index) / Double(particleCount - 1)
        let particleProgress = normalized(progress - tailOffset * trailSpan)
        let point = canvasPoint(
            progress: particleProgress,
            detailScale: detailScale,
            origin: origin,
            scale: scale
        )
        let fade = pow(1 - tailOffset, 0.56)
        let radius = CGFloat(0.9 + fade * 2.7) * scale
        let opacity = (isDarkMode ? 0.05 : 0.10) + fade * (isDarkMode ? 0.95 : 0.90)
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.fill(
            Path(ellipseIn: rect),
            with: .color(particleColor(index: index, opacity: opacity, isDarkMode: isDarkMode))
        )

        if index < 6 {
            let glowRadius = radius * 1.8
            let glowRect = CGRect(
                x: point.x - glowRadius,
                y: point.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [
                        PortfolixTheme.violet.opacity((isDarkMode ? 0.18 : 0.24) * opacity),
                        .clear
                    ]),
                    center: point,
                    startRadius: 0,
                    endRadius: glowRadius
                )
            )
        }
    }

    private static func particleColor(index: Int, opacity: Double, isDarkMode: Bool) -> Color {
        let phase = index % 6
        let adjustedOpacity = isDarkMode ? opacity : min(1, opacity * 1.08)
        switch phase {
        case 0, 1:
            return PortfolixTheme.violet.opacity(adjustedOpacity)
        case 2, 3:
            return PortfolixTheme.lilac.opacity(adjustedOpacity * (isDarkMode ? 0.94 : 1))
        case 4:
            return PortfolixTheme.rose.opacity(adjustedOpacity * (isDarkMode ? 0.82 : 0.92))
        default:
            return PortfolixTheme.blue.opacity(adjustedOpacity * (isDarkMode ? 0.72 : 0.82))
        }
    }

    private static func canvasPoint(
        progress: Double,
        detailScale: Double,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        let theta = progress * 2 * Double.pi
        let radius = orbitRadius - detailAmplitude * detailScale * cos(petalCount * theta)
        let x = 50 + cos(theta) * radius * curveScale
        let y = 50 + sin(theta) * radius * curveScale
        return CGPoint(
            x: origin.x + CGFloat(x) * scale,
            y: origin.y + CGFloat(y) * scale
        )
    }

    private static func detailScale(at time: TimeInterval) -> Double {
        let pulseAngle = normalized(time / pulseDuration) * 2 * Double.pi
        return 0.52 + ((sin(pulseAngle + 0.55) + 1) / 2) * 0.48
    }

    private static func normalized(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}
