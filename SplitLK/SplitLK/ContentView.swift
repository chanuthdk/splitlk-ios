import SwiftUI

struct ContentView: View {
    /// Set when a reminder is tapped. Switching to the Groups tab is handled
    /// here; selecting the group itself is left to `GroupsView`, which is the
    /// only view that knows how to find it.
    @Binding var groupToOpen: UUID?

    @State private var screen: Screen = .groups

    /// Named Screen rather than Tab: SwiftUI gained a `Tab` type of its own,
    /// and a nested enum with that name is ambiguous at the use site.
    enum Screen { case groups, insights, settings }

    var body: some View {
        TabView(selection: $screen) {
            GroupsView(groupToOpen: $groupToOpen)
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(Screen.groups)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.pie.fill") }
                .tag(Screen.insights)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Screen.settings)
        }
        .onChange(of: groupToOpen) { _, id in
            guard id != nil else { return }
            screen = .groups
        }
    }
}
