import SwiftUI
import CalCore

struct CalendarPickerView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @StateObject private var sync = AppSyncManager()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("All your calendars stay synced automatically.")
                    Text("Each widget shows the calendars you pick for it. To choose them, touch and hold a widget on your Home Screen, tap **Edit Widget**, then **Select Calendars**.")
                        .foregroundStyle(.secondary)
                    if !sync.status.isEmpty {
                        Text(sync.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Choosing calendars")
            }

            Section {
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    HStack {
                        Text("Sync now")
                        if sync.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(sync.isSyncing)
            }

            Section {
                CalendarGridView(
                    entry: CalendarEntryBuilder.live(weekCount: 2),
                    interactive: false
                )
                .frame(height: 170) // ~systemMedium
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
                .id("grid-\(sync.status)") // rebuild after sync

                HStack {
                    Spacer()
                    AgendaView(
                        entry: AgendaEntryBuilder.live(),
                        interactive: false
                    )
                    .frame(width: 170, height: 146) // ~systemSmall
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer()
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
                .id("agenda-\(sync.status)")
            } header: {
                Text("Widget preview")
            } footer: {
                Text("Live from your synced calendars; empty means no events in that range.")
            }
        }
        .navigationTitle(auth.email ?? "Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign out") { auth.signOut() }
            }
        }
        .task {
            sync.rebind(auth: auth)
            await sync.loadCalendars()
        }
    }
}
