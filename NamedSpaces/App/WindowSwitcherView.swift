import SwiftUI
import AppKit

struct WindowSwitcherItem: Identifiable {
    let id: Int
    let icon: NSImage
    let title: String
    let isSelected: Bool
}

struct WindowSwitcherSnapshot {
    let items: [WindowSwitcherItem]
    let title: String
    let emptyMessage: String
}

struct WindowSwitcherView: View {
    let snapshot: WindowSwitcherSnapshot
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if snapshot.items.isEmpty {
                Text(snapshot.emptyMessage)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(for item: WindowSwitcherItem) -> some View {
        Button {
            onSelect(item.id)
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
                .foregroundStyle(item.isSelected ? .white : .white.opacity(0.85))
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
        return AnyShapeStyle(.white.opacity(0.06))
    }
}
