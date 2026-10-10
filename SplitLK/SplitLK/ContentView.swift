import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("SplitLK")
                    .font(.largeTitle.bold())
                Text("Scan a receipt, split the bill, settle up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Groups")
        }
    }
}

#Preview {
    ContentView()
}
