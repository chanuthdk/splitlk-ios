import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderDays") private var reminderDays = 3
    @AppStorage("requireBiometrics") private var requireBiometrics = true

    @Environment(SyncService.self) private var sync
    /// Owned by the app, not created here. It is the notification centre's
    /// delegate, so it has to outlive this screen.
    @Environment(NotificationService.self) private var notifications

    @State private var showingResetConfirm = false
    @State private var pending: [PendingReminder] = []

    @FetchRequest(sortDescriptors: []) private var groups: FetchedResults<CDGroup>

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                securitySection
                notificationsSection
                if remindersEnabled && !pending.isEmpty {
                    scheduledSection
                }
                preferencesSection

                Section {
                    Button("Reset all data", role: .destructive) {
                        showingResetConfirm = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle("Settings")
            .task {
                await notifications.refreshAuthorization()
                await refreshPending()
            }
            .confirmationDialog("Delete all groups, bills and settlements?",
                                isPresented: $showingResetConfirm,
                                titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    // MARK: - Sections

    private var syncSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(syncTint)
                        .frame(width: 7, height: 7)
                    Text(syncLabel)
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Button("Sync all groups now") {
                Task {
                    for group in groups { await sync.push(group) }
                }
            }
            .disabled(groups.isEmpty)
        } header: {
            Text("Sync")
        } footer: {
            Text("Groups sync in the background while you use the app. Everything works offline and uploads when you're back online.")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Require \(biometryName)", isOn: $requireBiometrics)
        } header: {
            Text("Security")
        } footer: {
            Text("Balances are hidden until you unlock, and the app re-locks whenever it goes into the background.")
        }
    }

    private var notificationsSection: some View {
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
                            groupID: groups.first?.groupID,
                            groupName: groups.first?.displayName ?? "SplitLK"
                        )
                        await refreshPending()
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            if remindersEnabled && !notifications.isAuthorized {
                Text("Notifications are turned off for SplitLK in iOS Settings.")
            } else if remindersEnabled {
                Text("A reminder is scheduled for each group with an outstanding balance. Swipe one down to settle up or put it off a day.")
            } else {
                Text("A reminder is scheduled for each group where a balance is still outstanding.")
            }
        }
    }

    /// Shows what is actually queued. A notification feature that schedules
    /// something days away is otherwise impossible to tell apart from one
    /// that quietly did nothing.
    private var scheduledSection: some View {
        Section {
            ForEach(pending) { reminder in
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .font(.subheadline.weight(.medium))
                    Text(reminder.body)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                    if let date = reminder.fireDate {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(Palette.stamp)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Scheduled")
        }
    }

    private var preferencesSection: some View {
        Section {
            LabeledContent("Home currency", value: "LKR")

            LabeledContent("Item categories") {
                Text(CategoryClassifier.isModelAvailable ? "On-device model" : "Keyword matching")
                    .foregroundStyle(Palette.inkSoft)
            }

            Button("Forget category corrections") {
                CategoryClassifier.forgetCorrections()
            }
        } header: {
            Text("Preferences")
        } footer: {
            Text("Scanned items are categorised on your device. Changing an item's category teaches it for next time.")
        }
    }

    // MARK: - Status

    private var syncLabel: String {
        switch sync.status {
        case .idle:               return "Waiting"
        case .syncing:            return "Syncing…"
        case .synced(let date):   return "Synced \(date.formatted(.dateTime.hour().minute()))"
        case .failed:             return "Offline"
        }
    }

    private var syncTint: Color {
        switch sync.status {
        case .failed:  return Palette.owing
        case .synced:  return Palette.owed
        case .syncing: return Palette.stamp
        case .idle:    return Palette.rule
        }
    }

    /// The toggle used to say "Face ID" on every device, including ones
    /// without it.
    private var biometryName: String {
        BiometricService.label
    }

    // MARK: - Actions

    private func handleReminderToggle(_ enabled: Bool) async {
        guard enabled else {
            notifications.cancelAll()
            await refreshPending()
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
        await refreshPending()
    }

    private func refreshPending() async {
        pending = await notifications.pendingReminders()
    }

    private func resetAll() {
        for group in groups {
            context.delete(group)
        }
        try? context.save()
        notifications.cancelAll()
        Task { await refreshPending() }
    }
}
