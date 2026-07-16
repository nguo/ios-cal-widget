import SwiftUI
import CalCore

struct CalendarPickerView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @StateObject private var sync = AppSyncManager()
    @State private var previewOffset = 0

    var body: some View {
        List {
            Section {
                ForEach(sync.sources) { source in
                    Button {
                        sync.toggle(source.id)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: source.colorHex))
                                .frame(width: 14, height: 14)
                            Text(source.summary)
                                .foregroundStyle(.primary)
                            Spacer()
                            if source.isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Calendars")
            } footer: {
                if !sync.status.isEmpty { Text(sync.status) }
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
                    entry: CalendarEntryBuilder.live(weekCount: 2, offsetOverride: previewOffset),
                    interactive: false
                )
                .frame(height: 170) // ~systemMedium
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
                .id("\(sync.status)-\(previewOffset)") // rebuild after sync or page change

                HStack {
                    Button { previewOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Button("This week") { previewOffset = 0 }
                    Spacer()
                    Button { previewOffset += 1 } label: { Image(systemName: "chevron.right") }
                }
            } header: {
                Text("Widget preview")
            } footer: {
                Text("Live from your synced calendars. Use the arrows to page \u{00B1}2 weeks; empty means no events in that range.")
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
