import SwiftUI
import CoreData
import FirebaseCore

@main
struct SplitLKApp: App {
    let persistenceController = PersistenceController.shared

    @State private var biometrics = BiometricService()
    @State private var sync = SyncService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Configured once at launch, before any Firestore call is made.
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if biometrics.isUnlocked {
                    ContentView()
                        .environment(sync)
                } else {
                    LockView(service: biometrics)
                        .task { await biometrics.authenticate() }
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .task {
                // Signing in early means the first sync does not pay for it,
                // and a failure here is silent: the app works offline anyway.
                try? await sync.signIn()
            }
            .onChange(of: scenePhase) { _, phase in
                // Re-lock when the app leaves the foreground, so balances
                // are not visible to someone picking up an unlocked phone.
                if phase == .background {
                    biometrics.lock()
                    sync.stopAll()
                }
            }
        }
    }
}
