import SwiftUI

/// Settings window: searchable sidebar of app pages and providers, grouped-form detail pages.
struct SettingsContent: View {
    @ObservedObject var appState: AppState

    /// Selected page persists across window close/reopen via UserDefaults.
    @AppStorage("settingsSelectedPage") private var selectedRaw: String = SettingsPage.general.rawValue
    @State private var query = ""

    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { currentPage },
            set: { if let page = $0 { selectedRaw = page.rawValue } }
        )
    }

    private var currentPage: SettingsPage {
        let page = SettingsPage(rawValue: selectedRaw) ?? .general
        if case .provider(let id) = page, !providerIDs.contains(id) { return .general }
        return page
    }

    /// Providers in the user's popover order, limited to ones Settings knows how to configure.
    private var providerIDs: [String] {
        Self.listedProviderIDs(order: appState.config.providerOrder, discoveredClaudeIDs: appState.claudeAccountIDs)
    }

    /// A second Claude account is listed while its folder is signed in — whether or not a
    /// reading has arrived yet, so its toggle is there even when the first fetch failed.
    nonisolated static func listedProviderIDs(order: [String], discoveredClaudeIDs: Set<String>) -> [String] {
        order.filter { id in
            guard ProviderCatalog.info(for: id) != nil else { return false }
            return id == "claude" || !isClaudeProviderID(id) || discoveredClaudeIDs.contains(id)
        }
    }

    /// Claude accounts' pages carry the card's live name ("Claude · b@x").
    private func info(for id: String) -> ProviderSettingsInfo? {
        ProviderCatalog.info(for: id, liveName: appState.providers.first { $0.id == id }?.name)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail(for: currentPage)
                .id(currentPage)
        }
        .frame(minWidth: SettingsDesign.windowMinWidth, minHeight: SettingsDesign.windowMinHeight)
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                ForEach(SettingsPage.appPages.filter { $0.matches(query) }) { page in
                    SidebarRow(title: page.title, tile: IconTile(symbol: page.icon))
                        .tag(page)
                }
            }

            if !visibleProviderIDs.isEmpty {
                Section("Providers") {
                    ForEach(visibleProviderIDs, id: \.self) { id in
                        providerRow(id)
                    }
                    // Reordering a filtered list would map indices onto the wrong providers.
                    .onMove(perform: moveAction)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
    }

    private var visibleProviderIDs: [String] {
        providerIDs.filter { SettingsPage.provider($0).matches(query) }
    }

    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard query.isEmpty else { return nil }
        return { source, destination in moveProviders(from: source, to: destination) }
    }

    @ViewBuilder
    private func providerRow(_ id: String) -> some View {
        if let info = info(for: id) {
            SidebarRow(title: info.name, tile: IconTile(symbol: info.icon, tint: info.tint)) {
                ProviderSidebarBadge(
                    provider: appState.providers.first { $0.id == id },
                    enabled: appState.config.isProviderEnabled(id)
                )
            }
            .tag(SettingsPage.provider(id))
        }
    }

    @ViewBuilder
    private func detail(for page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage(appState: appState)
        case .display: DisplayPage(appState: appState)
        case .howItWorks:
            HowItWorksPage { page in
                query = ""  // a filtered sidebar might not list the page being opened
                selectedRaw = page.rawValue
            }
        case .about: AboutPage(appState: appState)
        case .provider(let id):
            if let info = info(for: id) {
                ProviderPage(info: info, appState: appState)
            }
        }
    }

    /// `onMove` offsets index into the visible provider list; apply them to the full order,
    /// which also holds ids Settings doesn't list.
    private func moveProviders(from source: IndexSet, to destination: Int) {
        var visible = providerIDs
        visible.move(fromOffsets: source, toOffset: destination)
        var order = appState.config.providerOrder
        let listed = Set(providerIDs)
        let slots = order.indices.filter { listed.contains(order[$0]) }
        for (slot, id) in zip(slots, visible) {
            order[slot] = id
        }
        appState.updateProviderOrder(order)
    }
}

/// Sidebar entry: tile, title, optional trailing accessory.
private struct SidebarRow<Accessory: View>: View {
    let title: String
    let tile: IconTile
    @ViewBuilder var accessory: () -> Accessory

    init(title: String, tile: IconTile, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.tile = tile
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            tile
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            accessory()
        }
        .padding(.vertical, 2)
    }
}

/// What a provider is doing, at a glance: its highest usage, Off, Set Up, or an error.
private struct ProviderSidebarBadge: View {
    let provider: Provider?
    let enabled: Bool

    var body: some View {
        if !enabled {
            Text("Off")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            switch provider?.status {
            case .loaded where (provider?.maxPercentage ?? 0) == 0:
                // Spend- and balance-only providers have no meaningful percentage.
                Text("On")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .loaded:
                Text("\(Int(provider?.maxPercentage ?? 0))%")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(UsageLevel(percentage: provider?.maxPercentage ?? 0) == .critical
                        ? AnyShapeStyle(UsageLevel.critical.color) : AnyShapeStyle(.secondary))
            case .error(let message):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(UsageLevel.warning.color)
                    .help(message)
            case .notConnected, nil:
                pill("Set Up", tint: .accentColor)
            case .loading:
                EmptyView()
            }
        }
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

/// Grouped-form container every Settings page uses, so all pages share one look.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}
