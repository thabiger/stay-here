import SwiftUI
import Core

struct UpdateView: View {
    let updateInfo: UpdateInfo
    let onDownload: () -> Void
    let onViewReleaseNotes: () -> Void
    let onLater: () -> Void

    private var publishedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: updateInfo.publishedAt)
    }

    private var notesPreview: String {
        let trimmed = updateInfo.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No release notes were included for this version."
        }

        if trimmed.count <= 700 {
            return trimmed
        }

        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 700)
        return trimmed[..<cutoff].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Update Available")
                    .font(.largeTitle.bold())
                Text("StayHere \(updateInfo.version) was published on \(publishedDateText).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(updateInfo.title)
                    .font(.headline)
                ScrollView {
                    Text(notesPreview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 180, maxHeight: 240)
            }

            HStack {
                Button("Later", action: onLater)
                Spacer()
                Button("View Release Notes", action: onViewReleaseNotes)
                Button("Download Update", action: onDownload)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 320)
    }
}
