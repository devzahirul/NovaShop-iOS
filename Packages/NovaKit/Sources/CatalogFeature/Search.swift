import DesignSystem
import Domain
import NovaCore
import ProductUI
import Routing
import SwiftUI

@MainActor
@Observable
public final class SearchViewModel {
    public var text = ""
    public private(set) var popular: [String] = []
    public private(set) var suggestions: [Product] = []

    @ObservationIgnored private let catalog: any CatalogRepository
    @ObservationIgnored private let history: SearchHistoryStore
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let debounce: Duration

    public init(
        catalog: any CatalogRepository,
        history: SearchHistoryStore,
        clock: any Clock<Duration> = ContinuousClock(),
        debounce: Duration = .milliseconds(250)
    ) {
        self.catalog = catalog
        self.history = history
        self.clock = clock
        self.debounce = debounce
    }

    public var recent: [String] {
        history.terms
    }

    public func loadPopular() async {
        popular = await (try? catalog.popularSearches()) ?? []
    }

    /// Debounced type-ahead. Called from `.task(id: text)`: every keystroke cancels the previous
    /// task, so the sleep *is* the debounce — no Combine, no timers, no manual bookkeeping.
    public func updateSuggestions() async {
        let term = text.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            suggestions = []
            return
        }
        do {
            try await clock.sleep(for: debounce)
            let results = try await catalog.search(ProductQuery(text: term))
            suggestions = Array(results.prefix(6))
        } catch {
            // Cancelled by the next keystroke, or transient failure — suggestions are best-effort.
        }
    }

    public func submit(_ term: String? = nil) -> ProductQuery? {
        let value = (term ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        history.record(value)
        return ProductQuery(text: value)
    }

    public func clearHistory() {
        history.clear()
    }
}

/// Search (design 07). Native `.searchable` for keyboard, dictation and accessibility behaviour.
public struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @Environment(Router.self) private var router

    public init(viewModel: @autoclosure @escaping () -> SearchViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        List {
            if viewModel.text.trimmingCharacters(in: .whitespaces).count >= 2 {
                suggestionsSection
            } else {
                termsSection("Popular Searches", terms: viewModel.popular, icon: "magnifyingglass")
                if !viewModel.recent.isEmpty {
                    termsSection("Recent Searches", terms: viewModel.recent, icon: "clock.arrow.circlepath", clearable: true)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .novaScreenBackground()
        .navigationTitle("Search")
        .searchable(text: $viewModel.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for products, brands…")
        .onSubmit(of: .search) { submit(nil) }
        .task { await viewModel.loadPopular() }
        .task(id: viewModel.text) { await viewModel.updateSuggestions() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CartToolbarButton() } }
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(viewModel.suggestions) { product in
                Button {
                    router.push(.product(product.id, preview: product))
                } label: {
                    HStack(spacing: Spacing.md) {
                        RemoteImage(product.primaryImageURL)
                            .frame(width: 44, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(product.name).font(NovaFont.body).foregroundStyle(NovaColor.textPrimary)
                            Text(Money.format(product.price)).font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            Button {
                submit(nil)
            } label: {
                Label("See all results for “\(viewModel.text)”", systemImage: "arrow.right")
                    .font(NovaFont.callout.weight(.medium))
                    .foregroundStyle(NovaColor.accent)
            }
            .listRowBackground(Color.clear)
        }
    }

    private func termsSection(_ title: String, terms: [String], icon: String, clearable: Bool = false) -> some View {
        Section {
            ForEach(terms, id: \.self) { term in
                Button {
                    submit(term)
                } label: {
                    Label(term, systemImage: icon)
                        .font(NovaFont.body)
                        .foregroundStyle(NovaColor.textPrimary)
                }
                .listRowBackground(Color.clear)
            }
        } header: {
            HStack {
                Text(title).font(NovaFont.headline).foregroundStyle(NovaColor.textPrimary)
                Spacer()
                if clearable {
                    Button("Clear") { viewModel.clearHistory() }
                        .font(NovaFont.caption)
                        .tint(NovaColor.accent)
                }
            }
            .textCase(nil)
        }
    }

    private func submit(_ term: String?) {
        guard let query = viewModel.submit(term) else { return }
        router.push(.searchResults(query))
    }
}
