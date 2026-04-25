import SwiftUI

struct PreparednessDetailSheet: View {
    let item: PreparednessChecklistItem
    @Binding var ignoredGapsRaw: String
    @Environment(\.dismiss) private var dismiss

    private var ignoredGapIDs: Set<String> {
        Set(ignoredGapsRaw.split(separator: "|").map(String.init))
    }

    private func toggleIgnore(_ gapID: String) {
        var current = ignoredGapIDs
        if current.contains(gapID) {
            current.remove(gapID)
        } else {
            current.insert(gapID)
        }
        ignoredGapsRaw = current.sorted().joined(separator: "|")
    }

    private var activeGaps: [PreparednessGap] {
        item.gaps.filter { !ignoredGapIDs.contains($0.id) }
    }

    private var ignoredGaps: [PreparednessGap] {
        item.gaps.filter { ignoredGapIDs.contains($0.id) }
    }

    private var activeGapsByPerson: [String: [PreparednessGap]] {
        Dictionary(grouping: activeGaps, by: { $0.personName ?? "Household" })
    }

    @ViewBuilder
    private func activeGapRow(_ gap: PreparednessGap) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.kataChampagne)
            VStack(alignment: .leading, spacing: 2) {
                Text(gap.documentTypeLabel).font(.subheadline.weight(.medium))
                if let detail = gap.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                toggleIgnore(gap.id)
            } label: {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Ignore this gap")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Active gaps grouped by person
                if !activeGapsByPerson.isEmpty {
                    ForEach(activeGapsByPerson.keys.sorted(), id: \.self) { personName in
                        Section(header: Text(personName).font(.headline)) {
                            ForEach(activeGapsByPerson[personName] ?? [], id: \.id) { gap in
                                activeGapRow(gap)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("All set — no missing items.").foregroundStyle(.secondary)
                    }
                }

                // Ignored disclosure (collapsible)
                if !ignoredGaps.isEmpty {
                    Section {
                        DisclosureGroup("Ignored (\(ignoredGaps.count))") {
                            ForEach(ignoredGaps, id: \.id) { gap in
                                HStack {
                                    Text(gap.documentTypeLabel).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Restore") { toggleIgnore(gap.id) }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
