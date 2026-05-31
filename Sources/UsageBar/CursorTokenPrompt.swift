import AppKit

/// Small glass-styled modal for entering the long Cursor session token.
@MainActor
enum CursorTokenPrompt {
    static func present(initial: String) -> String? {
        let controller = TokenPromptController(initial: initial)
        return controller.runModal()
    }
}

@MainActor
private final class TokenPromptController: NSObject, NSTextViewDelegate {
    private let window: GlassPanel
    private let textView = NSTextView()
    private var result: String?

    init(initial: String) {
        window = GlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 328),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configureWindow()
        buildContent(initial: initial)
    }

    func runModal() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.runModal(for: window)
        return result
    }

    private func configureWindow() {
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
    }

    private func buildContent(initial: String) {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        window.contentView = root

        let stroke = GlassStrokeView()
        root.addSubview(stroke)

        let title = label("Cursor session token", size: 22, weight: .semibold, alpha: 0.94)
        let subtitle = label(
            "Paste the WorkosCursorSessionToken cookie from a logged-in Cursor session.",
            size: 13.5,
            weight: .regular,
            alpha: 0.64
        )
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2

        let scroll = tokenField(initial: initial)
        let help = LinkButton(title: "How to find it", target: self, action: #selector(openHelp))
        let cancel = glassButton(title: "Cancel", action: #selector(cancel))
        let save = glassButton(title: "Save", action: #selector(save))
        save.keyEquivalent = "\r"

        [title, subtitle, scroll, help, cancel, save].forEach(root.addSubview)

        NSLayoutConstraint.activate([
            stroke.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stroke.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stroke.topAnchor.constraint(equalTo: root.topAnchor),
            stroke.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22),
            scroll.heightAnchor.constraint(equalToConstant: 128),

            help.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            help.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),

            save.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            save.widthAnchor.constraint(equalToConstant: 112),
            save.heightAnchor.constraint(equalToConstant: 38),

            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -12),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            cancel.widthAnchor.constraint(equalTo: save.widthAnchor),
            cancel.heightAnchor.constraint(equalTo: save.heightAnchor)
        ])

        if !initial.isEmpty {
            textView.setSelectedRange(NSRange(location: 0, length: (initial as NSString).length))
        }
    }

    private func tokenField(initial: String) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.13).cgColor
        scroll.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        scroll.layer?.borderWidth = 1

        textView.string = initial
        textView.delegate = self
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        scroll.documentView = textView
        return scroll
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.labelColor.withAlphaComponent(alpha)
        return field
    }

    private func glassButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentTintColor = .labelColor
        return button
    }

    @objc private func save() {
        result = textView.string
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        finish()
    }

    @objc private func cancel() {
        result = nil
        finish()
    }

    @objc private func openHelp() {
        if let url = URL(string: "https://cursor.com/dashboard") {
            NSWorkspace.shared.open(url)
        }
    }

    private func finish() {
        NSApp.stopModal()
        window.orderOut(nil)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            save()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        return false
    }
}

private final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class GlassStrokeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
        NSColor.white.withAlphaComponent(0.20).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class LinkButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        font = .systemFont(ofSize: 13.5, weight: .medium)
        contentTintColor = .controlAccentColor
    }
}
