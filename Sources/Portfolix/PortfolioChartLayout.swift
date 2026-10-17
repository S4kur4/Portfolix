import CoreGraphics
import Foundation

enum PortfolioChartLayout {
    static func barSegments(weights: [Double], size: CGSize, spacing: CGFloat = 2) -> [CGRect] {
        let weights = weights.map { $0.isFinite ? max($0, 0) : 0 }
        let total = weights.reduce(0, +)
        guard total > 0, size.width > 0, size.height > 0 else { return [] }
        let gap = min(max(spacing, 0), size.width / CGFloat(max(weights.count * 2, 1)))
        let available = max(size.width - gap * CGFloat(max(weights.count - 1, 0)), 0)
        var x: CGFloat = 0
        return weights.map { weight in
            let width = available * weight / total
            defer { x += width + gap }
            return CGRect(x: x, y: 0, width: width, height: size.height)
        }
    }

    // Balanced binary partitioning avoids the slivers of a single-axis layout.
    static func treemap(weights: [Double], in bounds: CGRect, spacing: CGFloat = 0) -> [CGRect] {
        guard bounds.width > 0, bounds.height > 0,
              bounds.width.isFinite, bounds.height.isFinite else { return [] }
        var rectangles = Array(repeating: CGRect.zero, count: weights.count)
        let gap = spacing.isFinite ? max(spacing, 0) : 0
        let entries = weights.enumerated().filter { $0.element.isFinite && $0.element > 0 }
        func partition(_ entries: ArraySlice<(offset: Int, element: Double)>, _ rect: CGRect) {
            guard let first = entries.first else { return }
            if entries.count == 1 {
                rectangles[first.offset] = rect
                return
            }
            let total = entries.reduce(0.0) { $0 + $1.element }
            var accumulated = 0.0
            var split = entries.startIndex + 1
            var bestDistance = Double.infinity
            for index in entries.indices.dropLast() {
                accumulated += entries[index].element
                let distance = abs(total / 2 - accumulated)
                if distance < bestDistance {
                    bestDistance = distance
                    split = index + 1
                }
            }
            let left = entries[..<split]
            let fraction = left.reduce(0.0) { $0 + $1.element } / total
            if rect.width >= rect.height {
                guard rect.width > gap else { return }
                let availableWidth = rect.width - gap
                let width = availableWidth * fraction
                partition(left, CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
                partition(entries[split...], CGRect(x: rect.minX + width + gap, y: rect.minY, width: availableWidth - width, height: rect.height))
            } else {
                guard rect.height > gap else { return }
                let availableHeight = rect.height - gap
                let height = availableHeight * fraction
                partition(left, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height))
                partition(entries[split...], CGRect(x: rect.minX, y: rect.minY + height + gap, width: rect.width, height: availableHeight - height))
            }
        }
        partition(entries[...], bounds)
        return rectangles
    }
}
