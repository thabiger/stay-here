import AppKit

final class SetupChecklistAccessoryView: NSView {
    private let stackView = NSStackView()

    convenience init(status: StayHereSetupStatus) {
        self.init(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        refresh(with: status)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(with status: StayHereSetupStatus) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for item in StayHereSetupCheck.checklistItems(for: status) {
            stackView.addArrangedSubview(makeRow(for: item))
        }
    }

    private func makeRow(for item: SetupChecklistItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: item.isSatisfied ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: nil
        )
        icon.contentTintColor = item.isSatisfied ? .systemGreen : .secondaryLabelColor
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
        case .inputMonitoring: return 2
        case .missionControlShortcuts: return 3
        }
    }

    private func fixTarget(for tag: Int) -> SetupChecklistItem.FixTarget? {
        switch tag {
        case 1: return .accessibility
        case 2: return .inputMonitoring
        case 3: return .missionControlShortcuts
        default: return nil
        }
    }
}
