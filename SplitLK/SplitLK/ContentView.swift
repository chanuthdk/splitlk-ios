import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            GroupsView()
                .tabItem { Label("Groups", systemImage: "person.3.fill") }

            Text("Insights")
                .tabItem { Label("Insights", systemImage: "chart.pie.fill") }

            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
