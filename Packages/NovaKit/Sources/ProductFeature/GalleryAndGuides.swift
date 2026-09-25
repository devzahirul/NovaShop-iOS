import DesignSystem
import Domain
import SwiftUI

// MARK: - Image gallery (design 12)

/// Full-screen, pinch-to-zoom gallery with a thumbnail strip.
struct ImageGalleryView: View {
    let imageURLs: [URL]
    @State private var index: Int?
    @Environment(\.dismiss) private var dismiss

    init(imageURLs: [URL], startIndex: Int) {
        self.imageURLs = imageURLs
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
                Spacer()
                Text("\((index ?? 0) + 1)/\(imageURLs.count)")
                    .font(NovaFont.callout.monospacedDigit())
                    .foregroundStyle(NovaColor.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Spacing.lg)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { offset, url in
                        ZoomableImage(url: url)
                            .containerRelativeFrame(.horizontal)
                            .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $index)
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { offset, url in
                        Button {
                            withAnimation(.snappy) { index = offset }
                        } label: {
                            RemoteImage(url)
                                .frame(width: 56, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.sm)
                                        .strokeBorder(offset == index ? NovaColor.accent : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Image \(offset + 1)")
                        .accessibilityAddTraits(offset == index ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, Spacing.md)
        .novaScreenBackground()
    }
}

/// Pinch to zoom, double-tap to toggle 2×, drag to pan while zoomed.
struct ZoomableImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        RemoteImage(url, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(max(baseScale * value.magnification, 1), 4) }
                    .onEnded { _ in
                        baseScale = scale
                        if scale == 1 {
                            resetPan()
                        }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in baseOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    scale = scale > 1 ? 1 : 2
                    baseScale = scale
                    if scale == 1 {
                        resetPan()
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Product image")
            .accessibilityAddTraits(.isImage)
            .accessibilityZoomAction { action in
                scale = action.direction == .zoomIn ? min(scale + 1, 4) : max(scale - 1, 1)
                baseScale = scale
            }
    }

    private func resetPan() {
        offset = .zero
        baseOffset = .zero
    }
}

// MARK: - Size guide (design 13)

struct SizeGuideView: View {
    enum Unit: String, CaseIterable, Identifiable {
        case inches = "Inches", centimeters = "CM"
        var id: String {
            rawValue
        }
    }

    private struct Row: Identifiable {
        let size: String
        let bust: ClosedRange<Int>
        let waist: ClosedRange<Int>
        let hip: ClosedRange<Int>
        var id: String {
            size
        }
    }

    private let rows: [Row] = [
        Row(size: "XS", bust: 31 ... 32, waist: 24 ... 25, hip: 34 ... 35),
        Row(size: "S", bust: 33 ... 34, waist: 26 ... 27, hip: 36 ... 37),
        Row(size: "M", bust: 35 ... 36, waist: 28 ... 29, hip: 38 ... 39),
        Row(size: "L", bust: 37 ... 38, waist: 30 ... 31, hip: 40 ... 41),
        Row(size: "XL", bust: 39 ... 40, waist: 32 ... 33, hip: 42 ... 43),
    ]

    @State private var unit: Unit = Locale.current.measurementSystem == .metric ? .centimeters : .inches
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Picker("Unit", selection: $unit) {
                        ForEach(Unit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Grid(horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
                        GridRow {
                            ForEach(["Size", "Bust", "Waist", "Hip"], id: \.self) {
                                Text($0).font(NovaFont.headline).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                        .background(NovaColor.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm))
                        ForEach(rows) { row in
                            GridRow {
                                Text(row.size).font(NovaFont.headline)
                                Text(format(row.bust))
                                Text(format(row.waist))
                                Text(format(row.hip))
                            }
                            .font(NovaFont.body.monospacedDigit())
                            .frame(maxWidth: .infinity)
                            Divider().gridCellUnsizedAxes(.horizontal)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("How to Measure").font(NovaFont.title3).accessibilityAddTraits(.isHeader)
                        HStack(alignment: .top, spacing: Spacing.xl) {
                            Image(systemName: "figure.stand")
                                .font(.system(size: 90, weight: .ultraLight))
                                .foregroundStyle(NovaColor.accent)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                step(1, "Bust", "Measure around the fullest part of your chest.")
                                step(2, "Waist", "Measure at your natural waistline.")
                                step(3, "Hip", "Measure around the fullest part of your hips.")
                            }
                        }
                    }
                }
                .padding(Spacing.screen)
            }
            .novaScreenBackground()
            .navigationTitle("Size Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(NovaColor.accent) }
            }
        }
        .presentationDetents([.large])
    }

    private func format(_ range: ClosedRange<Int>) -> String {
        switch unit {
        case .inches: "\(range.lowerBound)-\(range.upperBound)"
        case .centimeters: "\(Int((Double(range.lowerBound) * 2.54).rounded()))-\(Int((Double(range.upperBound) * 2.54).rounded()))"
        }
    }

    private func step(_ number: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text("\(number)")
                .font(NovaFont.caption.weight(.bold))
                .foregroundStyle(NovaColor.onAccent)
                .frame(width: 22, height: 22)
                .background(NovaColor.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NovaFont.headline)
                Text(body).font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reviews (design 14)

public struct ReviewsView: View {
    @State private var viewModel: ReviewsViewModel

    public init(viewModel: @autoclosure @escaping () -> ReviewsViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            case let .failed(error):
                ErrorStateView(error) { Task { await viewModel.load() } }
            case let .loaded(page):
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    RatingSummary(stats: page.stats)
                    HStack(spacing: Spacing.sm) {
                        ForEach(ReviewFilter.allCases) { filter in
                            Chip(filter.title, isSelected: viewModel.filter == filter) { viewModel.filter = filter }
                        }
                    }
                    if viewModel.visibleReviews.isEmpty {
                        Text("No reviews match this filter yet.")
                            .font(NovaFont.body)
                            .foregroundStyle(NovaColor.textSecondary)
                            .padding(.vertical, Spacing.xl)
                    }
                    ForEach(viewModel.visibleReviews) { ReviewRow(review: $0) }
                }
                .padding(Spacing.screen)
                .animation(.snappy, value: viewModel.filter)
            }
        }
        .novaScreenBackground()
        .navigationTitle("Reviews (\(viewModel.product.reviewCount))")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

struct RatingSummary: View {
    let stats: ReviewStats

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xl) {
            VStack(spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Image(systemName: "star.fill").foregroundStyle(NovaColor.star)
                    Text(stats.average.formatted(.number.precision(.fractionLength(1))))
                        .font(NovaFont.display)
                }
                Text("out of 5").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                Text("\(stats.total) reviews").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
            }
            VStack(spacing: Spacing.xs) {
                ForEach((1 ... 5).reversed(), id: \.self) { star in
                    let share = stats.distribution[star, default: 0]
                    HStack(spacing: Spacing.sm) {
                        Text("\(star)★").font(NovaFont.caption.monospacedDigit()).frame(width: 24, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(NovaColor.surfaceMuted)
                                Capsule().fill(NovaColor.accent).frame(width: proxy.size.width * share)
                            }
                        }
                        .frame(height: 6)
                        Text(share.formatted(.percent.precision(.fractionLength(0))))
                            .font(NovaFont.caption.monospacedDigit())
                            .foregroundStyle(NovaColor.textSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(star) stars, \(share.formatted(.percent.precision(.fractionLength(0))))")
                }
            }
        }
        .novaCard()
    }
}
