import AppKit
import QuartzCore
import SwiftUI

struct AIReportRoseOrbit: View {
    let date: Date
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoseOrbitLayerRepresentable(
            isAnimated: !reduceMotion && date.timeIntervalSinceReferenceDate != 0,
            isDarkMode: colorScheme == .dark
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct RoseOrbitLayerRepresentable: NSViewRepresentable {
    let isAnimated: Bool
    let isDarkMode: Bool

    func makeNSView(context: Context) -> RoseOrbitLayerView {
        let view = RoseOrbitLayerView()
        view.update(isAnimated: isAnimated, isDarkMode: isDarkMode)
        return view
    }

    func updateNSView(_ nsView: RoseOrbitLayerView, context: Context) {
        nsView.update(isAnimated: isAnimated, isDarkMode: isDarkMode)
    }
}

@MainActor
private final class RoseOrbitLayerView: NSView {
    private var requestedAnimation = true
    private var requestedDarkMode = true
    private var renderedSize = CGSize.zero
    private var renderedAnimation = false
    private var renderedDarkMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        rebuildIfNeeded()
    }

    func update(isAnimated: Bool, isDarkMode: Bool) {
        requestedAnimation = isAnimated
        requestedDarkMode = isDarkMode
        rebuildIfNeeded()
    }

    private func rebuildIfNeeded() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        guard
            size != renderedSize
                || requestedAnimation != renderedAnimation
                || requestedDarkMode != renderedDarkMode
        else {
            return
        }

        renderedSize = size
        renderedAnimation = requestedAnimation
        renderedDarkMode = requestedDarkMode
        rebuildLayers(size: size, isAnimated: requestedAnimation, isDarkMode: requestedDarkMode)
    }

    private func rebuildLayers(size: CGSize, isAnimated: Bool, isDarkMode: Bool) {
        guard let rootLayer = layer else { return }
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        rootLayer.frame = CGRect(origin: .zero, size: size)

        let rotationLayer = CALayer()
        rotationLayer.frame = rootLayer.bounds
        rotationLayer.masksToBounds = false
        rootLayer.addSublayer(rotationLayer)

        let pulseLayer = CALayer()
        pulseLayer.frame = rotationLayer.bounds
        pulseLayer.masksToBounds = false
        rotationLayer.addSublayer(pulseLayer)

        let path = RoseOrbitGeometry.path(in: pulseLayer.bounds)
        addPathLayer(path: path, to: pulseLayer, size: size, isDarkMode: isDarkMode)

        if isAnimated {
            addAnimatedParticles(path: path, to: pulseLayer, size: size, isDarkMode: isDarkMode)
            addContainerAnimations(rotationLayer: rotationLayer, pulseLayer: pulseLayer)
        } else {
            addStaticParticles(to: pulseLayer, size: size, isDarkMode: isDarkMode)
        }
    }

    private func addPathLayer(
        path: CGPath,
        to parent: CALayer,
        size: CGSize,
        isDarkMode: Bool
    ) {
        let pathLayer = CAShapeLayer()
        pathLayer.frame = parent.bounds
        pathLayer.path = path
        pathLayer.fillColor = nil
        pathLayer.strokeColor = RoseOrbitPalette.violet(
            isDarkMode: isDarkMode,
            alpha: isDarkMode ? 0.34 : 0.30
        )
        pathLayer.lineWidth = max(1, min(size.width, size.height) * 0.047)
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round
        parent.addSublayer(pathLayer)
    }

    private func addAnimatedParticles(
        path: CGPath,
        to parent: CALayer,
        size: CGSize,
        isDarkMode: Bool
    ) {
        let side = min(size.width, size.height)
        let dotDiameter = max(2.4, side * 0.068)
        let dotsPerFamily = RoseOrbitGeometry.particleCount / RoseParticleFamily.allCases.count
        let instanceDelay = RoseOrbitGeometry.orbitDuration
            * RoseOrbitGeometry.trailSpan
            / Double(dotsPerFamily)
        let trailWarmup = instanceDelay * Double(dotsPerFamily)
        let currentTime = CACurrentMediaTime()
        let startPoint = RoseOrbitGeometry.point(progress: 0, in: parent.bounds)

        for family in RoseParticleFamily.allCases {
            let replicator = CAReplicatorLayer()
            replicator.frame = parent.bounds
            replicator.instanceCount = dotsPerFamily
            replicator.instanceDelay = instanceDelay
            replicator.instanceAlphaOffset = -0.022

            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
            particle.cornerRadius = dotDiameter / 2
            particle.position = startPoint
            particle.backgroundColor = RoseOrbitPalette.color(
                family: family,
                isDarkMode: isDarkMode,
                alpha: 0.98
            )

            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.path = path
            movement.calculationMode = .paced
            movement.duration = RoseOrbitGeometry.orbitDuration
            movement.repeatCount = .infinity
            movement.beginTime = currentTime
                - trailWarmup
                - Double(family.rawValue) * RoseOrbitGeometry.orbitDuration
                    / Double(RoseOrbitGeometry.particleCount)
            movement.fillMode = .both
            movement.isRemovedOnCompletion = false
            particle.add(movement, forKey: "rose-orbit-position")

            replicator.addSublayer(particle)
            parent.addSublayer(replicator)
        }
    }

    private func addStaticParticles(to parent: CALayer, size: CGSize, isDarkMode: Bool) {
        let side = min(size.width, size.height)
        let staticParticleCount = 48
        for index in 0..<staticParticleCount {
            let tailOffset = Double(index) / Double(staticParticleCount - 1)
            let progress = RoseOrbitGeometry.normalized(0.18 - tailOffset * RoseOrbitGeometry.trailSpan)
            let fade = pow(1 - tailOffset, 0.56)
            let diameter = max(1.6, side * CGFloat(0.025 + fade * 0.045))
            let point = RoseOrbitGeometry.point(progress: progress, in: CGRect(origin: .zero, size: size))
            let particle = CALayer()
            particle.frame = CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            particle.cornerRadius = diameter / 2
            particle.backgroundColor = RoseOrbitPalette.color(
                family: RoseParticleFamily.allCases[index % RoseParticleFamily.allCases.count],
                isDarkMode: isDarkMode,
                alpha: max(0.08, fade)
            )
            parent.addSublayer(particle)
        }
    }

    private func addContainerAnimations(rotationLayer: CALayer, pulseLayer: CALayer) {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = RoseOrbitGeometry.rotationDuration
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        rotationLayer.add(rotation, forKey: "rose-orbit-rotation")

        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [0.97, 1.02, 0.97]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.duration = RoseOrbitGeometry.pulseDuration
        pulse.repeatCount = .infinity
        pulse.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        pulse.isRemovedOnCompletion = false
        pulseLayer.add(pulse, forKey: "rose-orbit-pulse")
    }
}

private enum RoseOrbitGeometry {
    static let particleCount = 176
    static let trailSpan = 0.4
    static let orbitDuration = 5.0
    static let rotationDuration = 20.0
    static let pulseDuration = 10.0

    private static let visualScale: CGFloat = 0.9
    private static let pathSteps = 240
    private static let orbitRadius = 7.0
    private static let detailAmplitude = 2.7
    private static let detailScale = 0.76
    private static let petalCount = 7.0
    private static let curveScale = 4.0

    static func path(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        for index in 0...pathSteps {
            let progress = Double(index) / Double(pathSteps)
            let point = point(progress: progress, in: bounds)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    static func point(progress: Double, in bounds: CGRect) -> CGPoint {
        let side = min(bounds.width, bounds.height)
        let visualSide = side * visualScale
        let origin = CGPoint(
            x: bounds.midX - visualSide / 2,
            y: bounds.midY - visualSide / 2
        )
        let scale = visualSide / 100
        let theta = normalized(progress) * 2 * Double.pi
        let radius = orbitRadius - detailAmplitude * detailScale * cos(petalCount * theta)
        return CGPoint(
            x: origin.x + CGFloat(50 + cos(theta) * radius * curveScale) * scale,
            y: origin.y + CGFloat(50 + sin(theta) * radius * curveScale) * scale
        )
    }

    static func normalized(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}

private enum RoseParticleFamily: Int, CaseIterable {
    case highlight
    case light
    case brand
    case deep
}

private enum RoseOrbitPalette {
    static func color(
        family: RoseParticleFamily,
        isDarkMode: Bool,
        alpha: Double
    ) -> CGColor {
        let hex: UInt32 = switch family {
        case .highlight: isDarkMode ? 0xC3B1FF : 0xAF9AFF
        case .light: isDarkMode ? 0xA995FF : 0x927BEE
        case .brand: isDarkMode ? 0x8C75FF : 0x7253DB
        case .deep: isDarkMode ? 0x8068EF : 0x654BC8
        }
        return cgColor(hex: hex, alpha: alpha)
    }

    static func violet(isDarkMode: Bool, alpha: Double) -> CGColor {
        cgColor(hex: isDarkMode ? 0x8C75FF : 0x7253DB, alpha: alpha)
    }

    private static func cgColor(hex: UInt32, alpha: Double) -> CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
