import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: GoogleAuthService

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Two Week Calendar")
                .font(.title.bold())
            Text("Sign in with Google to show your calendars in the widget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task { await auth.signIn() }
            } label: {
                Text("Sign in with Google")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            if let error = auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
            }
        }
        .padding()
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
    }
}
