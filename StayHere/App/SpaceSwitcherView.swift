import AppKit
import Core
import SwiftUI

struct SpaceSwitcherItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let isSelected: Bool
    let isCurrent: Bool
    let isEnabled: Bool
}

struct SpaceSwitcherSnapshot: Equatable {
    let items: [SpaceSwitcherItem]
    let title: String
}

struct SpaceSwitcherView: View {
    let snapshot: SpaceSwitcherSnapshot
    let onSelect: (Int) -> Void
    let updateInfo: UpdateInfo?
    let onOpenUpdate: (() -> Void)?

    init(
        snapshot: SpaceSwitcherSnapshot,
        onSelect: @escaping (Int) -> Void,
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
            Text(snapshot.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.items) { item in
                        row(for: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
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
                    Text("v\(updateInfo.version) available")
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

    @ViewBuilder
    private func row(for item: SpaceSwitcherItem) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            rowContent(for: item)
        }
        .buttonStyle(.plain)
        .disabled(item.isEnabled == false)
        .opacity(item.isEnabled ? 1 : 0.58)
    }

    private func rowContent(for item: SpaceSwitcherItem) -> some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(.system(size: 14.5, weight: item.isSelected ? .semibold : .regular, design: .default))
                .foregroundStyle(item.isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if item.isEnabled == false {
                Text("Unavailable")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.isSelected ? .white.opacity(0.9) : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground(for: item))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func selectionBackground(for item: SpaceSwitcherItem) -> some ShapeStyle {
        if item.isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.92))
        }
        if item.isCurrent {
            return AnyShapeStyle(Color.primary.opacity(0.06))
        }
        return AnyShapeStyle(.clear)
    }
}
