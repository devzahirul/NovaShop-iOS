import SwiftUI

/// Wrapping flow layout (chips, swatches). A real `Layout`, so it sizes correctly inside scroll
/// views and adapts to Dynamic Type without GeometryReader tricks.
public struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    public init(spacing: CGFloat = Spacing.sm, lineSpacing: CGFloat = Spacing.sm) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var cursorY = bounds.minY
        for row in arrange(proposal: proposal, subviews: subviews) {
            var cursorX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let origin = CGPoint(x: cursorX, y: cursorY + (row.height - size.height) / 2)
                subviews[index].place(at: origin, proposal: ProposedViewSize(size))
                cursorX += size.width + spacing
            }
            cursorY += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Two-thumb range slider for the price filter. Fully accessible: each thumb is an adjustable
/// element VoiceOver users can swipe up/down on.
public struct RangeSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    let step: Double

    public init(range: Binding<ClosedRange<Double>>, in bounds: ClosedRange<Double>, step: Double = 5) {
        _range = range
        self.bounds = bounds
        self.step = step
    }

    private let thumb: CGFloat = 24
    private static let space = "RangeSlider"

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - thumb
            let lowerX = position(of: range.lowerBound, width: width)
            let upperX = position(of: range.upperBound, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(NovaColor.border).frame(height: 3).padding(.horizontal, thumb / 2)
                Capsule().fill(NovaColor.accent)
                    .frame(width: max(upperX - lowerX, 0), height: 3)
                    .offset(x: lowerX + thumb / 2)
                thumbView(label: "Minimum price", value: range.lowerBound)
                    .offset(x: lowerX)
                    .gesture(DragGesture(coordinateSpace: .named(Self.space)).onChanged { drag in
                        let value = value(at: drag.location.x - thumb / 2, width: width)
                        range = min(value, range.upperBound - step) ... range.upperBound
                    })
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment ? step : -step
                        range = clamp(range.lowerBound + delta, upper: range.upperBound - step) ... range.upperBound
                    }
                thumbView(label: "Maximum price", value: range.upperBound)
                    .offset(x: upperX)
                    .gesture(DragGesture(coordinateSpace: .named(Self.space)).onChanged { drag in
                        let value = value(at: drag.location.x - thumb / 2, width: width)
                        range = range.lowerBound ... max(value, range.lowerBound + step)
                    })
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment ? step : -step
                        range = range.lowerBound ... clamp(range.upperBound + delta, lower: range.lowerBound + step)
                    }
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: 44)
    }

    private func thumbView(label: String, value: Double) -> some View {
        Circle()
            .fill(NovaColor.surface)
            .overlay { Circle().strokeBorder(NovaColor.accent, lineWidth: 2) }
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(.horizontal, -10)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Money.format(Decimal(value)))
    }

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        return CGFloat((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * width
    }

    private func value(at offset: CGFloat, width: CGFloat) -> Double {
        let ratio = min(max(offset / max(width, 1), 0), 1)
        let raw = bounds.lowerBound + Double(ratio) * (bounds.upperBound - bounds.lowerBound)
        return (raw / step).rounded() * step
    }

    private func clamp(_ value: Double, lower: Double? = nil, upper: Double? = nil) -> Double {
        min(max(value, lower ?? bounds.lowerBound), upper ?? bounds.upperBound)
    }
}
