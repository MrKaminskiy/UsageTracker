import SwiftUI

struct SettingsContent: View {
    @ObservedObject var appState: AppState

    /// Selected tab persists across window close/reopen via UserDefaults.
    @AppStorage("settingsSelectedTab") private var selectedRaw: String = SettingsTabKind.general.rawValue

    /// Optional callback the window controller uses to update its title.
    var onTabChanged: ((SettingsTabKind) -> Void)?

    private var selected: Binding<SettingsTabKind> {
        Binding(
            get: { SettingsTabKind(rawValue: selectedRaw) ?? .general },
            set: { newValue in
                selectedRaw = newValue.rawValue
                onTabChanged?(newValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbar(selected: selected)
            Group {
                switch selected.wrappedValue {
                case .general: GeneralTab(appState: appState)
                case .providers: ProvidersTab(appState: appState)
                case .display: DisplayTab(appState: appState)
                case .help: HelpTab()
                case .about: AboutTab(appState: appState)
                }
            }
            .id(selected.wrappedValue)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: selected.wrappedValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(
            minWidth: SettingsDesign.windowMinWidth,
            minHeight: SettingsDesign.windowMinHeight
        )
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            onTabChanged?(selected.wrappedValue)
        }
    }
}
