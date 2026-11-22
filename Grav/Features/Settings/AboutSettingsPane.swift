import AppKit
import SwiftUI

/// Clean, card-based About page ported 1:1 from Snapzy's `PreferencesAboutSettingsView` (Hand Mirror aesthetic).
struct AboutSettingsPane: View {
    let store: AntigravityTelemetryStore
    var onReplayWelcome: (() -> Void)?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Grav \(version) (\(build))"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    architectureCard
                    actionsCard
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)

            VStack(spacing: 3) {
                Text(verbatim: "Grav")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("Live flight-deck telemetry for Google Antigravity")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 420)
            }

            versionStatusLabel
                .padding(.top, 6)
        }
        .padding(.bottom, 4)
    }

    private var versionStatusLabel: some View {
        HStack(spacing: 6) {
            Text(appVersion)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.secondary)

            Text("•")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.5))

            Text(store.connectionStatus.isBrainAccessible ? "Local Telemetry Ready" : "Standby")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.secondary)
        }
    }

    // MARK: - Card 1: Architecture & Runtime

    private var architectureCard: some View {
        VStack(spacing: 0) {
            infoRow(label: "Notch Engine", value: "NotchKit 1.3.0")
            divider
            infoRow(label: "Platform", value: "macOS 14+ Native SwiftUI / AppKit")
            divider
            infoRow(label: "Telemetry", value: "Event-Driven Local kqueue")
            divider
            infoRow(label: "Interface", value: "Liquid Glass & Adaptive Chrome")
        }
        .aboutCardContainer(maxWidth: 480)
    }

    // MARK: - Card 2: Onboarding & Local Runtime

    private var actionsCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Welcome Experience")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary)

                Spacer()

                Button("Replay Welcome Screen") {
                    onReplayWelcome?()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            divider

            HStack(alignment: .center) {
                Text("Antigravity Brain")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary)

                Spacer()

                Button {
                    revealBrainFolder(store.connectionStatus.brainDirectoryURL)
                } label: {
                    HStack(spacing: 4) {
                        Text("Reveal in Finder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accentColor)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .aboutCardContainer(maxWidth: 480)
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary)

            Spacer(minLength: 20)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }

    private func revealBrainFolder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.activateFileViewerSelecting([parent])
            } else {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }
}

private extension View {
    func aboutCardContainer(maxWidth: CGFloat) -> some View {
        background {
            Radius.rect(Radius.card)
                .fill(Color.primary.opacity(0.04))
        }
        .clipShape(Radius.rect(Radius.card))
        .frame(maxWidth: maxWidth)
    }
}
