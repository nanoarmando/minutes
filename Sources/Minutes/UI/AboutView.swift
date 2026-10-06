import SwiftUI

struct AboutView: View {
    let environment: AppEnvironment
    private static let repository = URL(string: "https://github.com/nanoarmando/minutes")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
            Text("Minutes").font(.title.bold())
            Text("Version \(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))").foregroundStyle(.secondary)
            Text("Meeting notes recorded, transcribed and summarized on your Mac.")
            Text("© 2026 Jose Bianco · Licensed under AGPL-3.0").font(.callout).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 4) {
                Text("Transcription and speaker separation by FluidAudio.")
                Text("Speech recognition model Parakeet TDT v3 by NVIDIA.")
                Text("Parts of the meeting pipeline adapted from Muesli (MIT).")
            }
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Source code", destination: Self.repository)
                Link("License", destination: Self.repository.appending(path: "blob/main/LICENSE"))
            }
            Divider()
            UpdatesSection(updates: environment.updates, isAppBusy: environment.isBusy)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { environment.updates.check() }
    }

    private func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "dev"
    }
}

/// The result of the last update check, the release notes of a newer version and its Install button.
private struct UpdatesSection: View {
    let updates: UpdateCoordinator
    let isAppBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            status
            if case .available(let update) = updates.state {
                ScrollView {
                    Text(Self.markdown(update.notes))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                installRow(update)
            }
            if let error = updates.installError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var status: some View {
        HStack {
            switch updates.state {
            case .idle, .checking:
                ProgressView().controlSize(.small)
                Text("Checking for updates…").foregroundStyle(.secondary)
            case .unavailable(let reason):
                Text(reason).foregroundStyle(.secondary)
            case .upToDate:
                Label("Minutes is up to date", systemImage: "checkmark.circle")
            case .available(let update):
                Label("Minutes \(update.version.description) is available", systemImage: "arrow.down.circle")
            case .downloading(let update, let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("Downloading \(update.version.description)…").foregroundStyle(.secondary)
            case .verifying(let update):
                ProgressView().controlSize(.small)
                Text("Verifying \(update.version.description)…").foregroundStyle(.secondary)
            case .failed(let message):
                Label("Couldn't check for updates: \(message)", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            }
            Spacer()
            if case .failed = updates.state {
                Button("Retry") { updates.check() }
            } else if !updates.isWorking, updates.state != .unavailable(UpdateEligibility.developmentBuild.refusal ?? "") {
                Button("Check for Updates") { updates.check() }
            }
        }
    }

    @ViewBuilder private func installRow(_ update: AvailableUpdate) -> some View {
        HStack {
            if let refusal = UpdateEligibility.current.refusal {
                Text(refusal).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Link("Release page", destination: update.pageURL)
            } else {
                if isAppBusy { Text("Finish the recording first").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Link("Release page", destination: update.pageURL)
                Button("Install Update") { updates.install(update) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAppBusy)
            }
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
