import SwiftUI
import CoreData

@main
struct SplitLKApp: App {
    let persistenceController = PersistenceController.shared

    @State private var biometrics = BiometricService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if biometrics.isUnlocked {
                    ContentView()
                } else {
                    LockView(service: biometrics)
                        .task { await biometrics.authenticate() }
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .onChange(of: scenePhase) { _, phase in
                // Re-lock when the app leaves the foreground, so balances
                // are not visible to someone picking up an unlocked phone.
                if phase == .background {
                    biometrics.lock()
                }
            }
        }
    }
}
