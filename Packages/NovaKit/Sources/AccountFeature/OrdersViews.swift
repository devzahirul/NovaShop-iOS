import DesignSystem
import Domain
import NovaCore
import Routing
import SwiftUI

// MARK: - Orders list

@MainActor
@Observable
public final class OrdersViewModel {
    public enum Filter: String, CaseIterable, Identifiable {
        case all, processing, shipped, delivered
        public var id: String {
            rawValue
        }

        public var title: String {
            rawValue.capitalized
        }
    }

    public private(set) var state: LoadState<[Order]> = .idle
    public var filter: Filter = .all
    @ObservationIgnored private let service: any OrderService

    public init(service: any OrderService) {
        self.service = service
    }

    public var visibleOrders: [Order] {
        let orders = state.value ?? []
        switch filter {
        case .all: return orders
        case .processing: return orders.filter { [.placed, .processing].contains($0.status) }
        case .shipped: return orders.filter { [.shipped, .outForDelivery].contains($0.status) }
        case .delivered: return orders.filter { $0.status == .delivered }
        }
    }

    public func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            state = try await .loaded(service.orders())
        } catch is CancellationError {
        } catch {
            state = .failed(error.userFacing)
        }
    }
}

public struct OrdersView: View {
    @State private var viewModel: OrdersViewModel
    @Environment(Router.self) private var router

    public init(viewModel: @autoclosure @escaping () -> OrdersViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(OrdersViewModel.Filter.allCases) { filter in
                            Chip(filter.title, isSelected: viewModel.filter == filter) { viewModel.filter = filter }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                switch viewModel.state {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                case let .failed(error):
                    ErrorStateView(error) { Task { await viewModel.load() } }
                case .loaded where viewModel.visibleOrders.isEmpty:
                    EmptyStateView(
                        systemImage: "shippingbox",
                        title: "No orders yet",
                        message: "When you place an order it will show up here."
                    )
                    .frame(minHeight: 360)
                case .loaded:
                    ForEach(viewModel.visibleOrders) { order in
                        Button { router.push(.order(order)) } label: { OrderRow(order: order) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.screen)
        }
        .novaScreenBackground()
        .navigationTitle("My Orders")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

struct OrderRow: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Order #\(order.number)").font(NovaFont.headline).foregroundStyle(NovaColor.textPrimary)
                    Text("Placed \(order.placedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                }
                Spacer()
                StatusBadge(status: order.status)
            }
            HStack(spacing: -12) {
                ForEach(order.items.prefix(4)) { item in
                    RemoteImage(item.product.primaryImageURL)
                        .frame(width: 44, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(NovaColor.surface, lineWidth: 2) }
                }
                Spacer()
                Text(Money.format(order.pricing.total)).font(NovaFont.price).foregroundStyle(NovaColor.textPrimary)
            }
        }
        .novaCard()
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let status: OrderStatus

    var body: some View {
        Text(status.title)
            .font(NovaFont.eyebrow)
            .foregroundStyle(status == .delivered ? NovaColor.success : NovaColor.accent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(status == .delivered ? NovaColor.successMuted : NovaColor.accentMuted, in: Capsule())
    }
}

// MARK: - Order detail + tracking

public struct OrderDetailView: View {
    let order: Order
    @Environment(Router.self) private var router

    public init(order: Order) {
        self.order = order
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Order #\(order.number)").font(NovaFont.title3)
                        Spacer()
                        StatusBadge(status: order.status)
                    }
                    Text("Placed \(order.placedAt.formatted(date: .long, time: .shortened))")
                        .font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                }

                TrackingTimeline(status: order.status, placedAt: order.placedAt)
                    .novaCard()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Items").font(NovaFont.headline)
                    ForEach(order.items) { item in
                        HStack(spacing: Spacing.md) {
                            RemoteImage(item.product.primaryImageURL)
                                .frame(width: 56, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.product.name).font(NovaFont.body.weight(.medium))
                                Text("\(item.variantDescription) · Qty \(item.quantity)")
                                    .font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                            }
                            Spacer()
                            Text(Money.format(item.lineTotal)).font(NovaFont.price)
                        }
                    }
                }
                .novaCard()

                VStack(spacing: Spacing.md) {
                    PriceRow("Subtotal", value: Money.format(order.pricing.subtotal))
                    if order.pricing.discount > 0 {
                        PriceRow("Discount", value: "-\(Money.format(order.pricing.discount))", valueColor: NovaColor.success)
                    }
                    PriceRow("Shipping", value: (order.pricing.shipping ?? 0) == 0 ? "Free" : Money.format(order.pricing.shipping ?? 0))
                    PriceRow("Tax", value: Money.format(order.pricing.tax))
                    Divider()
                    PriceRow("Total", value: Money.format(order.pricing.total), emphasis: true)
                }
                .novaCard()

                Button("Request a Return") { router.push(.returnRequest(order)) }
                    .buttonStyle(.nova(.outline))
            }
            .padding(Spacing.screen)
        }
        .novaScreenBackground()
        .navigationTitle("Order Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TrackingTimeline: View {
    let status: OrderStatus
    let placedAt: Date

    var body: some View {
        let steps = OrderStatus.trackingSteps
        let currentIndex = steps.firstIndex(of: status) ?? 0
        VStack(alignment: .leading, spacing: 0) {
            Text("Order Tracking").font(NovaFont.headline).padding(.bottom, Spacing.md)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index <= currentIndex ? NovaColor.accent : NovaColor.surfaceMuted)
                            .frame(width: 14, height: 14)
                            .overlay {
                                if index == currentIndex {
                                    Circle().strokeBorder(NovaColor.accent.opacity(0.3), lineWidth: 6).frame(width: 26, height: 26)
                                }
                            }
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(index < currentIndex ? NovaColor.accent : NovaColor.border)
                                .frame(width: 2, height: 36)
                        }
                    }
                    .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(NovaFont.body.weight(index == currentIndex ? .semibold : .regular))
                            .foregroundStyle(index <= currentIndex ? NovaColor.textPrimary : NovaColor.textTertiary)
                        if index <= currentIndex {
                            Text(placedAt.addingTimeInterval(Double(index) * 3600 * 6).formatted(date: .abbreviated, time: .shortened))
                                .font(NovaFont.caption)
                                .foregroundStyle(NovaColor.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(index < currentIndex ? "Completed" : index == currentIndex ? "Current" : "Pending")
            }
        }
    }
}

// MARK: - Return request

public struct ReturnRequestView: View {
    let order: Order
    @State private var selectedItems: Set<CartItem.ID> = []
    @State private var reason = Reason.fit
    @State private var notes = ""
    @State private var isSubmitted = false
    @Environment(\.dismiss) private var dismiss

    enum Reason: String, CaseIterable, Identifiable {
        case fit = "Doesn't fit", quality = "Quality not as expected", color = "Different color than pictured", other = "Other"
        var id: String {
            rawValue
        }
    }

    public init(order: Order) {
        self.order = order
    }

    public var body: some View {
        Form {
            Section("Select Items") {
                ForEach(order.items) { item in
                    Button {
                        selectedItems.formSymmetricDifference([item.id])
                    } label: {
                        HStack {
                            Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(NovaColor.accent)
                            Text(item.product.name).foregroundStyle(NovaColor.textPrimary)
                            Spacer()
                            Text(item.variantDescription).font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                        }
                    }
                    .accessibilityAddTraits(selectedItems.contains(item.id) ? .isSelected : [])
                }
            }
            Section("Reason") {
                Picker("Reason", selection: $reason) {
                    ForEach(Reason.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Additional Notes") {
                TextField("Tell us more (optional)", text: $notes, axis: .vertical).lineLimit(3 ... 6)
            }
        }
        .tint(NovaColor.accent)
        .scrollContentBackground(.hidden)
        .novaScreenBackground()
        .safeAreaInset(edge: .bottom) {
            Button("Submit Return Request") { isSubmitted = true }
                .buttonStyle(.nova(.primary))
                .disabled(selectedItems.isEmpty)
                .padding(Spacing.screen)
                .background(.bar)
        }
        .navigationTitle("Return Request")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Return requested", isPresented: $isSubmitted) {
            Button("Done") { dismiss() }
        } message: {
            Text("We've emailed you a prepaid return label. Refunds are issued within 5 business days of receipt.")
        }
    }
}

// MARK: - Notifications

@MainActor
@Observable
public final class NotificationsViewModel {
    public private(set) var state: LoadState<[AppNotification]> = .idle
    @ObservationIgnored private let repository: any NotificationRepository

    public init(repository: any NotificationRepository) {
        self.repository = repository
    }

    public func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            state = try await .loaded(repository.notifications())
        } catch is CancellationError {
        } catch {
            state = .failed(error.userFacing)
        }
    }

    public func markAllRead() {
        guard var items = state.value else { return }
        for index in items.indices {
            items[index].isRead = true
        }
        state = .loaded(items)
    }
}

public struct NotificationsView: View {
    @State private var viewModel: NotificationsViewModel

    public init(viewModel: @autoclosure @escaping () -> NotificationsViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        List {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            case let .failed(error):
                ErrorStateView(error) { Task { await viewModel.load() } }.listRowBackground(Color.clear)
            case let .loaded(items):
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: icon(for: item.kind))
                            .foregroundStyle(NovaColor.accent)
                            .frame(width: 36, height: 36)
                            .background(NovaColor.accentMuted, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.title).font(NovaFont.body.weight(item.isRead ? .regular : .semibold))
                                Spacer()
                                Text(item.date, format: .relative(presentation: .named))
                                    .font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                            }
                            Text(item.body).font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
                        }
                        if !item.isRead {
                            Circle().fill(NovaColor.accent).frame(width: 8, height: 8).padding(.top, 6)
                                .accessibilityLabel("Unread")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .novaScreenBackground()
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") { viewModel.markAllRead() }.tint(NovaColor.accent)
            }
        }
        .task { await viewModel.load() }
    }

    private func icon(for kind: AppNotification.Kind) -> String {
        switch kind {
        case .order: "shippingbox"
        case .promotion: "tag"
        case .system: "bell"
        }
    }
}
