import SwiftUI
import CoreData
import FirebaseCore

@main
struct SplitLKApp: App {
    let persistenceController = PersistenceController.shared

    @State private var biometrics = BiometricService()
    @State private var sync = SyncService()
    /// Owned by the app rather than by the Settings screen. It is the
    /// notification centre's delegate, and a delegate that only exists while
    /// one tab is on screen stops handling taps the moment that tab is closed.
    @State private var notifications = NotificationService()
    @Environment(\.scenePhase) private var scenePhase

    /// Set when a reminder is tapped, so the Groups tab can open that group.
    @State private var groupToOpen: UUID?

    /// Mirrors the Settings toggle. When the user turns the lock off, the
    /// app opens straight to their groups instead of prompting.
    @AppStorage("requireBiometrics") private var requireBiometrics = true

    init() {
        // Configured once at launch, before any Firestore call is made.
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if biometrics.isUnlocked || !requireBiometrics {
                    ContentView(groupToOpen: $groupToOpen)
                        .environment(sync)
                        .environment(notifications)
                } else {
                    // The task covers a cold launch, where onChange sees no
                    // change because .active is the value it started at. The
                    // scenePhase handler below covers coming back to a locked
                    // app, where this view never disappeared so never re-runs.
                    // Overlapping is harmless: authenticate() ignores a second
                    // call while a prompt is already up.
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
            .task {
                await notifications.refreshAuthorization()
                notifications.onOpenGroup = { id in groupToOpen = id }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    // Re-lock when the app leaves the foreground, so balances
                    // are not visible to someone picking up an unlocked phone.
                    if requireBiometrics { biometrics.lock() }
                    sync.stopAll()

                case .active:
                    // Prompting here rather than from a `.task` on LockView:
                    // that task only runs when the view first appears, so
                    // coming back to a locked app left the user staring at a
                    // screen that never asked for anything.
                    if requireBiometrics && !biometrics.isUnlocked {
                        Task { await biometrics.authenticate() }
                    }

                default:
                    break
                }
            }
        }
    }
}
