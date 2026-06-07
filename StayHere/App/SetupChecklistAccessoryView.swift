import AppKit

final class SetupChecklistAccessoryView: NSView {
    static let preferredWidth: CGFloat = 1024

    private let rootStackView = NSStackView()
    private let checklistStackView = NSStackView()
    private let supplementaryLabel = NSTextField(wrappingLabelWithString: "")

    convenience init(status: StayHereSetupStatus, supplementaryText: NSAttributedString? = nil) {
        self.init(frame: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 220))
        if let supplementaryText {
            supplementaryLabel.attributedStringValue = supplementaryText
            supplementaryLabel.isHidden = false
        }
        refresh(with: status)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        supplementaryLabel.isHidden = true
        supplementaryLabel.isSelectable = false
        supplementaryLabel.lineBreakMode = .byWordWrapping
        supplementaryLabel.preferredMaxLayoutWidth = Self.preferredWidth

        checklistStackView.orientation = .vertical
        checklistStackView.alignment = .leading
        checklistStackView.spacing = 8

        rootStackView.orientation = .vertical
        rootStackView.alignment = .leading
        rootStackView.spacing = 12
        rootStackView.translatesAutoresizingMaskIntoConstraints = false
        rootStackView.addArrangedSubview(supplementaryLabel)
        rootStackView.addArrangedSubview(checklistStackView)
        addSubview(rootStackView)
        NSLayoutConstraint.activate([
            rootStackView.topAnchor.constraint(equalTo: topAnchor),
            rootStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(with status: StayHereSetupStatus) {
        checklistStackView.arrangedSubviews.forEach {
            checklistStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for item in StayHereSetupCheck.checklistItems(for: status) {
            checklistStackView.addArrangedSubview(makeRow(for: item))
        }
    }

    private func makeRow(for item: SetupChecklistItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: item.isSatisfied ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            accessibilityDescription: nil
        )
        icon.contentTintColor = item.isSatisfied ? .systemGreen : .systemRed
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
        row.addArrangedSubview(icon)

        if item.isSatisfied {
            row.addArrangedSubview(NSTextField(labelWithString: item.displayName))
        } else if let fixTarget = item.fixTarget {
            let button = NSButton(
                title: "\(item.displayName) (Click to fix)",
                target: self,
                action: #selector(openSettings(_:))
            )
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.contentTintColor = .linkColor
            button.tag = fixTargetTag(for: fixTarget)
            row.addArrangedSubview(button)
        } else {
            row.addArrangedSubview(NSTextField(labelWithString: item.displayName))
        }

        return row
    }

    @objc private func openSettings(_ sender: NSButton) {
        guard let target = fixTarget(for: sender.tag) else { return }
        StayHereSetupCheck.openSettings(for: target)
    }

    private func fixTargetTag(for target: SetupChecklistItem.FixTarget) -> Int {
        switch target {
        case .accessibility: return 1
        case .inputMonitoring: return 3
        case .missionControlShortcuts: return 2
        }
    }

    private func fixTarget(for tag: Int) -> SetupChecklistItem.FixTarget? {
        switch tag {
        case 1: return .accessibility
        case 2: return .missionControlShortcuts
        case 3: return .inputMonitoring
        default: return nil
        }
    }
}
