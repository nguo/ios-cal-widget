import SwiftUI
import CalCore

/// The app's only screen: the signed-in accounts, a manual sync, and previews of the widgets.
///
/// Calendars aren't picked here — each placed widget picks its own, and may mix calendars from
/// several accounts. What this screen owns is which accounts exist at all, since that's what
/// decides what the widget's picker can offer.
struct AccountsView: View {
    @EnvironmentObject private var accountManager: AccountManager
    @StateObject private var sync = AppSyncManager()
    @State private var catalog: CalendarCatalog?

    var body: some View {
        List {
            if accountManager.accounts.isEmpty {
                signInSection
            } else {
                accountsSection
                choosingCalendarsSection
                syncSection
            }
            previewSection
        }
        .navigationTitle("GCal Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private var signInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in with Google to show your calendars in the widgets.")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await add() }
                } label: {
                    Text("Sign in with Google").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                if let error = accountManager.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(accountManager.accounts, id: \.self) { email in
                VStack(alignment: .leading, spacing: 2) {
                    Text(email)
                    Text(calendarCountLabel(for: email))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                offsets.map { accountManager.accounts[$0] }.forEach(accountManager.removeAccount)
                Task { await refresh() }
            }
            Button("Add account") { Task { await add() } }
            if let error = accountManager.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Swipe an account to remove it.")
        }
    }

    private var choosingCalendarsSection: some View {
        Section {
            Text("Each widget shows the calendars you pick for it, and one widget can mix calendars from several accounts. To choose them, touch and hold a widget on your Home Screen, tap **Edit Widget**, then **Select Calendars**.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } header: {
            Text("Choosing calendars")
        } footer: {
            Text("Only the calendars a widget is showing get synced, so picking fewer keeps things fast.")
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task {
                    await sync.syncNow()
                    await refresh()
                }
            } label: {
                HStack {
                    Text("Sync now")
                    if sync.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(sync.isSyncing)
            if !sync.status.isEmpty {
                Text(sync.status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        Section {
            CalendarGridView(entry: WidgetFixtures.entry(), interactive: false)
                .frame(height: 170) // ~systemMedium
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)

            HStack {
                Spacer()
                AgendaView(entry: WidgetFixtures.agendaEntry(), interactive: false)
                    .frame(width: 170, height: 146) // ~systemSmall
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer()
            }
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 4)

            AgendaMediumView(entry: WidgetFixtures.agendaEntry(variant: .medium), interactive: false)
                .frame(height: 170) // ~systemMedium
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
        } header: {
            Text("Widget preview")
        } footer: {
            Text("Sample events — your widgets show your own synced calendars.")
        }
    }

    private func calendarCountLabel(for email: String) -> String {
        let count = catalog?.sources(for: email).count ?? 0
        guard count > 0 else { return "No calendars listed yet" }
        return count == 1 ? "1 calendar" : "\(count) calendars"
    }

    private func add() async {
        await accountManager.addAccount()
        // List the new account's calendars right away — nothing can be picked for a widget until
        // the catalog knows they exist.
        await SyncCoordinator.refreshCatalog(calendar: .calWidget)
        await refresh()
    }

    private func refresh() async {
        catalog = CatalogStore(appGroupIdentifier: AppConfig.appGroupID)?.read()
    }
}
