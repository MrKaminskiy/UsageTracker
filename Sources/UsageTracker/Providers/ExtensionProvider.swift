import Foundation

actor ExtensionProvider {
    private let server: ExtensionServer
    private let providerId: String
    private let providerName: String
    private let providerIcon: String
    private let dashboardURL: URL

    init(server: ExtensionServer, id: String, name: String, icon: String, dashboardURL: URL) {
        self.server = server
        self.providerId = id
        self.providerName = name
        self.providerIcon = icon
        self.dashboardURL = dashboardURL
    }

    func fetchUsage() async -> Provider {
        guard let data = await server.getData(for: providerId) else {
            return Provider(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                items: [],
                status: .notConnected(url: dashboardURL)
            )
        }

        let items = data.items.map { item in
            UsageItem(
                label: item.label,
                current: item.current,
                limit: item.limit,
                resetLabel: item.resetLabel
            )
        }

        return Provider(
            id: providerId,
            name: providerName,
            icon: providerIcon,
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded
        )
    }
}
