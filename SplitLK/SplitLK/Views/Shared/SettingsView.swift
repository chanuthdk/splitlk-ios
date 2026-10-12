import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderDays") private var reminderDays = 3
    @AppStorage("requireBiometrics") private var requireBiometrics = true

    @State private var notifications = NotificationService()
    @State private var showingResetConfirm = false

    @FetchRequest(sortDescriptors: []) private var groups: FetchedResults<CDGroup>

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    Toggle("Require Face ID", isOn: $requireBiometrics)
                }

                Section {
                    Toggle("Settle-up reminders", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, enabled in
                            Task { await handleReminderToggle(enabled) }
                        }

                    if remindersEnabled {
                        Picker("Remind after", selection: $reminderDays) {
                            ForEach([1, 3, 7, 14], id: \.self) { days in
                                Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                            }
                        }
                        .onChange(of: reminderDays) { _, _ in
                            Task { await rescheduleAll() }
                        }

                        Button("Send a test reminder") {
                            Task {
                                await notifications.scheduleDemoReminder(
                                    groupName: groups.first?.displayName ?? "SplitLK"
                                )
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if remindersEnabled && !notifications.isAuthorized {
                        Text("Notifications are turned off for SplitLK in iOS Settings.")
                    } else {
                        Text("A reminder is scheduled for each group where a balance is still outstanding.")
                    }
                }

                Section("Preferences") {
                    LabeledContent("Home currency", value: "LKR")
                }

                Section {
                    Button("Reset all data", role: .destructive) {
                        showingResetConfirm = true
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await notifications.refreshAuthorization() }
            .confirmationDialog("Delete all groups, bills and settlements?",
                                isPresented: $showingResetConfirm,
                                titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    // MARK: - Actions

    private func handleReminderToggle(_ enabled: Bool) async {
        guard enabled else {
            notifications.cancelAll()
            return
        }
        let granted = await notifications.requestAuthorization()
        if granted {
            await rescheduleAll()
        } else {
            remindersEnabled = false
        }
    }

    /// Reschedules every group's reminder based on its current balance.
    private func rescheduleAll() async {
        notifications.cancelAll()
        for group in groups {
            let balance = BalanceService.myBalance(in: group)
            guard balance != 0 else { continue }
            await notifications.scheduleSettleReminder(
                groupID: group.groupID,
                groupName: group.displayName,
                amount: abs(balance),
                isOwedToMe: balance > 0,
                afterDays: reminderDays
            )
        }
    }

    private func resetAll() {
        for group in groups {
            context.delete(group)
        }
        try? context.save()
        notifications.cancelAll()
    }
}
