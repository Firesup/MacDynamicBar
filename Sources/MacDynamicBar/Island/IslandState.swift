import Combine

enum IslandPresentation: Equatable {
    case compact
    case hover
    case expanded
}

/// Hover is transient; a click keeps the full island open after the pointer leaves.
@MainActor
final class IslandState: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .compact
    private var isHovered = false
    private let hoverEnabled: Bool

    var isExpanded: Bool { presentation == .expanded }

    init(hoverEnabled: Bool = true) { self.hoverEnabled = hoverEnabled }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        guard !isExpanded else { return }
        presentation = hovered && hoverEnabled ? .hover : .compact
    }

    func toggle() {
        presentation = isExpanded ? (isHovered && hoverEnabled ? .hover : .compact) : .expanded
    }

    func collapse() {
        isHovered = false
        presentation = .compact
    }
}
