import SwiftUI

/// "Correct with instructions…": one step. The instructions become word replacements, which are applied to the
/// transcript and the glossary; the instructions are saved; the summary is regenerated and the meeting re-tagged.
/// If asking the model fails, nothing changes and the error is shown with Retry.
struct CorrectionSheet: View {
    let environment: AppEnvironment
    let model: MeetingsModel
    let note: NoteSummary
    @State var instructions: String
    @Environment(\.dismiss) private var dismiss
    @State private var step: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Correct with instructions").font(.headline)
            Text("Describe what the transcript got wrong, in your own words, for example “Doctor Grim is DrGreenlife; Pablo Veliz works at VNS”.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .disabled(step != nil)
            if let step {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(step).foregroundStyle(.secondary)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.disabled(step != nil)
                Button(error == nil ? "Apply" : "Retry", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step != nil || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func apply() {
        guard let service = environment.summaryService else {
            error = "A summary provider is needed. Configure one in Settings › Summaries."
            return
        }
        let text = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        Task {
            do {
                step = "Asking the model…"
                let document = try String(contentsOf: note.url, encoding: .utf8)
                var context = environment.meetingContext(for: note, document: document)
                context.instructions = text
                let corrections = try await CorrectionService(service: service)
                    .replacements(instructions: text, transcript: NoteFile.transcriptSection(of: document), context: context)

                step = "Applying corrections…"
                let writer = NoteWriter(folder: note.url.deletingLastPathComponent())
                if !corrections.isEmpty {
                    try writer.applyCorrections(corrections, to: note.url, id: note.id)
                    environment.glossary.merge(corrections)
                }
                try writer.updateSidecar(id: note.id) { $0.instructions = text }

                step = "Regenerating the summary…"
                let type = environment.summaryTypes.type(id: note.summaryType ?? "") ?? environment.summaryTypes.defaultType
                await model.regenerate(note, type: type)
                step = "Re-tagging…"
                await environment.retag(note)
                step = nil
                if let failure = model.regenerateError {
                    error = "The corrections were applied, but the summary failed: \(failure)"
                } else {
                    dismiss()
                }
            } catch {
                step = nil
                self.error = error.localizedDescription
            }
        }
    }
}
