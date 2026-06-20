import SwiftUI
import AppKit
import Core

struct WindowSwitcherView: View {
    let snapshot: WindowSwitcherSnapshot
    let onSelect: (WindowEntry) -> Void
    let updateInfo: UpdateInfo?
    let onOpenUpdate: (() -> Void)?

    init(
        snapshot: WindowSwitcherSnapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        updateInfo: UpdateInfo? = nil,
        onOpenUpdate: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelect = onSelect
        self.updateInfo = updateInfo
        self.onOpenUpdate = onOpenUpdate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.leading, 72)

            if snapshot.spaceGroups.isEmpty {
                emptyState
            } else if snapshot.showSpaceLabels {
                groupedBody
            } else {
                flatBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if let updateInfo {
                Button {
                    onOpenUpdate?()
                } label: {
                    Text("New version v\(updateInfo.version) available")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: snapshot.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(snapshot.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        Text(snapshot.emptyMessage)
            .font(.system(size: 14.5, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
    }

    private var flatBody: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(snapshot.spaceGroups.flatMap(\.items)) { item in
                    row(for: item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private var groupedBody: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.spaceGroups) { group in
                    spaceSection(group: group)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func spaceSection(group: WindowSwitcherSpaceGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.tertiary)
                    .frame(width: 5, height: 5)
                Text(group.spaceLabel.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                Spacer()
                Text("\(group.items.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            ForEach(group.items) { item in
                row(for: item)
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func row(for item: WindowSwitcherItem) -> some View {
        Button {
            onSelect(item.entry)
        } label: {
            rowContent(for: item)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(for item: WindowSwitcherItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(item.title)
                .font(.system(size: 14.5, weight: item.isSelected ? .semibold : .regular, design: .default))
                .foregroundStyle(item.isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground(for: item))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func selectionBackground(for item: WindowSwitcherItem) -> some ShapeStyle {
        if item.isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.92))
        }
        return AnyShapeStyle(Color.primary.opacity(0.06))
    }
}
