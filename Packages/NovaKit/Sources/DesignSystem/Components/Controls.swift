import SwiftUI

// MARK: - Chip

/// Pill-shaped selectable chip (category filters, sizes, review filters).
public struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(NovaFont.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? NovaColor.onAccent : NovaColor.textPrimary)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 34)
                .background(isSelected ? NovaColor.accent : NovaColor.surfaceMuted, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Square selectable box used for sizes (XS S M L XL).
public struct SizeBox: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, isAvailable: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.isAvailable = isAvailable
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(NovaFont.callout.weight(.medium))
                .foregroundStyle(isSelected ? NovaColor.onAccent : NovaColor.textPrimary)
                .strikethrough(!isAvailable)
                .frame(minWidth: 44, minHeight: 40)
                .padding(.horizontal, Spacing.xs)
                .background(isSelected ? NovaColor.accent : NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(isSelected ? .clear : NovaColor.border)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel("Size \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Colour swatch

public struct ColorSwatch: View {
    let hex: String
    let name: String
    let isSelected: Bool
    let diameter: CGFloat

    public init(hex: String, name: String, isSelected: Bool = false, diameter: CGFloat = 28) {
        self.hex = hex
        self.name = name
        self.isSelected = isSelected
        self.diameter = diameter
    }

    public var body: some View {
        Circle()
            .fill(Color(hex: hex))
            .overlay { Circle().strokeBorder(Color.black.opacity(0.08)) }
            .frame(width: diameter, height: diameter)
            .padding(3)
            .overlay {
                Circle().strokeBorder(isSelected ? NovaColor.accent : .clear, lineWidth: 1.5)
            }
            .accessibilityLabel(name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Rating

public struct RatingView: View {
    let rating: Double
    let count: Int?
    let starSize: Font

    public init(rating: Double, count: Int? = nil, starSize: Font = .caption2) {
        self.rating = rating
        self.count = count
        self.starSize = starSize
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            HStack(spacing: 1) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Image(systemName: symbol(for: index))
                        .font(starSize)
                        .foregroundStyle(NovaColor.star)
                }
            }
            if let count {
                Text("\(rating.formatted(.number.precision(.fractionLength(1)))) (\(count))")
                    .font(NovaFont.caption)
                    .foregroundStyle(NovaColor.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1)))) out of 5" +
            (count.map { ", \($0) reviews" } ?? ""))
    }

    private func symbol(for index: Int) -> String {
        let value = rating - Double(index)
        if value >= 0.75 {
            return "star.fill"
        }
        if value >= 0.25 {
            return "star.leadinghalf.filled"
        }
        return "star"
    }
}

// MARK: - Quantity

public struct QuantityStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    public init(value: Binding<Int>, range: ClosedRange<Int> = 1 ... 10) {
        _value = value
        self.range = range
    }

    public var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Decrease quantity", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(NovaFont.callout.monospacedDigit())
                .frame(minWidth: 22)
                .contentTransition(.numericText(value: Double(value)))
            stepButton("plus", label: "Increase quantity", enabled: value < range.upperBound) { value += 1 }
        }
        .background(NovaColor.surfaceMuted, in: Capsule())
        .animation(.snappy, value: value)
        .sensoryFeedback(.increase, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quantity")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where value < range.upperBound: value += 1
            case .decrement where value > range.lowerBound: value -= 1
            default: break
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(enabled ? NovaColor.textPrimary : NovaColor.textTertiary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Radio row

public struct RadioIndicator: View {
    let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? NovaColor.accent : NovaColor.border, lineWidth: 1.5)
            if isSelected {
                Circle().fill(NovaColor.accent).padding(5)
            }
        }
        .frame(width: 20, height: 20)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Selectable card row with a radio indicator (shipping option, address, payment method).
public struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    public init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.md) {
                RadioIndicator(isSelected: isSelected).padding(.top, 2)
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.lg)
            .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? NovaColor.accent : NovaColor.border, lineWidth: isSelected ? 1.2 : 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Section header

public struct SectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(NovaFont.title3)
                .foregroundStyle(NovaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: Spacing.xs) {
                        Text(actionTitle)
                        Image(systemName: "arrow.right").imageScale(.small)
                    }
                    .font(NovaFont.callout.weight(.medium))
                    .foregroundStyle(NovaColor.accent)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Checkout step indicator

public struct StepIndicator: View {
    let steps: [String]
    let current: Int

    public init(steps: [String], current: Int) {
        self.steps = steps
        self.current = current
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: Spacing.xs) {
                    HStack(spacing: 0) {
                        line(active: index <= current).opacity(index == 0 ? 0 : 1)
                        Circle()
                            .fill(index <= current ? NovaColor.accent : NovaColor.surface)
                            .overlay { Circle().strokeBorder(index <= current ? .clear : NovaColor.border, lineWidth: 1.5) }
                            .overlay {
                                if index < current {
                                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(NovaColor.onAccent)
                                }
                            }
                            .frame(width: 16, height: 16)
                        line(active: index < current).opacity(index == steps.count - 1 ? 0 : 1)
                    }
                    Text(step)
                        .font(NovaFont.caption.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index <= current ? NovaColor.accent : NovaColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(steps.count), \(steps[min(current, steps.count - 1)])")
    }

    private func line(active: Bool) -> some View {
        Rectangle().fill(active ? NovaColor.accent : NovaColor.border).frame(height: 1.5)
    }
}

// MARK: - Toggle row

public struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(NovaFont.body).foregroundStyle(NovaColor.textPrimary)
                if let subtitle {
                    Text(subtitle).font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                }
            }
        }
        .tint(NovaColor.accent)
        .frame(minHeight: 44)
    }
}

// MARK: - Price row

public struct PriceRow: View {
    let title: String
    let value: String
    let emphasis: Bool
    let valueColor: Color

    public init(_ title: String, value: String, emphasis: Bool = false, valueColor: Color = NovaColor.textPrimary) {
        self.title = title
        self.value = value
        self.emphasis = emphasis
        self.valueColor = valueColor
    }

    public var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(emphasis ? NovaColor.textPrimary : NovaColor.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .font(emphasis ? NovaFont.headline : NovaFont.body)
        .accessibilityElement(children: .combine)
    }
}
