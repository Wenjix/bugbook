import SwiftUI

struct BrowserCleanupSheet: View {
    @Binding var proposals: [BrowserCleanupProposal]
    let isApplyingCleanup: Bool
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clean Browser Pages")
                .font(.system(size: 18, weight: .semibold))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($proposals) { $proposal in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(proposal.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(proposal.urlString)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(proposal.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Picker("Decision", selection: $proposal.decision) {
                                Text("Keep").tag(BrowserCleanupDecision.keep)
                                Text("Save").tag(BrowserCleanupDecision.save)
                                Text("Read Later").tag(BrowserCleanupDecision.readLater)
                                Text("Close").tag(BrowserCleanupDecision.close)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button(isApplyingCleanup ? "Applying…" : "Apply All", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplyingCleanup)
            }
        }
        .padding(24)
        .frame(width: 720, height: 520)
    }
}
