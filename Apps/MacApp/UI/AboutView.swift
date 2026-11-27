import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("BlueLink")
                    .font(.title2.weight(.semibold))
                Text("Version \(model.appVersion) (\(model.buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("A small menu bar app that connects and disconnects the Bluetooth device you choose when your display wakes and sleeps.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 7) {
                bullet("No background helper, cloud account, telemetry or ads.")
                bullet("No pairing or unpairing. No Bluetooth power changes.")
                bullet("Logs stay local and are sanitized before export.")
            }
            .frame(maxWidth: 380, alignment: .leading)

            authorCard

            Spacer(minLength: 0)

            Text("MIT License · © 2026 Dylan Liu")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bullet(_ text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Uses the public GitHub avatar like Daybreak, with the same image bundled
    /// as an offline fallback so About never shows an empty placeholder.
    private var authorCard: some View {
        HStack(alignment: .center, spacing: 12) {
            authorAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text("Dylan Liu")
                    .font(.headline)
                Text("BlueLink Author")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Link(destination: Self.authorEmailURL) {
                        Label("mentalflow@ourdocs.cn", systemImage: "envelope")
                    }
                    Link(destination: Self.authorGitHubURL) {
                        Label("github.com/mentalfl0w", systemImage: "link")
                    }
                }
                .font(.caption2)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var authorAvatar: some View {
        AsyncImage(url: Self.authorAvatarURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image("AuthorAvatar")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private static let authorGitHubURL = URL(string: "https://github.com/mentalfl0w")!
    private static let authorEmailURL = URL(string: "mailto:mentalflow@ourdocs.cn")!
    private static let authorAvatarURL = URL(string: "https://avatars.githubusercontent.com/u/30333935?v=4")!
}
