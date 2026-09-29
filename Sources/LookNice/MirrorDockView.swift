import AppKit

/// Small hover-revealed control bar shown inside the Mirror: Face / Eyes crop
/// toggles plus a Transparent toggle.
final class MirrorDockView: NSView {
    var onFaceTapped: (() -> Void)?
    var onEyesTapped: (() -> Void)?
    var onTransparentTapped: (() -> Void)?

    private let faceButton = MirrorDockView.makeButton(symbol: "person.crop.square", tooltip: "Face")
    private let eyesButton = MirrorDockView.makeButton(symbol: "eye", tooltip: "Eyes")
    private let transparentButton = MirrorDockView.makeButton(symbol: "circle.lefthalf.filled", tooltip: "Transparent")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = frameRect.height / 2
        alphaValue = 0

        faceButton.target = self
        faceButton.action = #selector(faceTapped)
        eyesButton.target = self
        eyesButton.action = #selector(eyesTapped)
        transparentButton.target = self
        transparentButton.action = #selector(transparentTapped)

        let stack = NSStackView(views: [faceButton, eyesButton, transparentButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// While faded out, don't intercept clicks meant for dragging the Mirror.
    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.05 ? nil : super.hitTest(point)
    }

    private static func makeButton(symbol: String, tooltip: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .white
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 18),
            button.heightAnchor.constraint(equalToConstant: 18)
        ])
        return button
    }

    @objc private func faceTapped() { onFaceTapped?() }
    @objc private func eyesTapped() { onEyesTapped?() }
    @objc private func transparentTapped() { onTransparentTapped?() }
}
