import AppKit
import SwiftUI

extension View {
    func iconActionHelp(_ title: String) -> some View {
        modifier(IconActionHelp(title: title))
    }

    func iconActionTooltips() -> some View {
        overlayPreferenceValue(IconActionTooltipKey.self) { tooltip in
            if let tooltip {
                GeometryReader { geometry in
                    TooltipPosition(anchor: geometry[tooltip.bounds]) {
                        Text(tooltip.title)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary)
                            }
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct IconActionHelp: ViewModifier {
    let title: String
    @State private var hovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(title)
            .background {
                IconActionHover { inside in
                    guard hovering != inside else { return }
                    hovering = inside
                    if !inside { visible = false }
                }
                .accessibilityHidden(true)
            }
            .task(id: hovering) {
                guard hovering else { return }
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return }
                visible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                hovering = false
                visible = false
            }
            .anchorPreference(key: IconActionTooltipKey.self, value: .bounds) { bounds in
                visible ? IconActionTooltip(title: title, bounds: bounds) : nil
            }
    }
}

private struct IconActionHover: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: view
        ))
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) { view.changed = changed }

    final class TrackingView: NSView {
        var changed: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func mouseEntered(with event: NSEvent) { changed?(true) }
        override func mouseMoved(with event: NSEvent) { changed?(true) }
        override func mouseExited(with event: NSEvent) { changed?(false) }
    }
}

private struct IconActionTooltip {
    let title: String
    let bounds: Anchor<CGRect>
}

private struct IconActionTooltipKey: PreferenceKey {
    static var defaultValue: IconActionTooltip? { nil }

    static func reduce(value: inout IconActionTooltip?, nextValue: () -> IconActionTooltip?) {
        if let tooltip = nextValue() { value = tooltip }
    }
}

private struct TooltipPosition: Layout {
    let anchor: CGRect
    private let margin: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let tooltip = subviews.first else { return }
        let size = tooltip.sizeThatFits(.init(width: max(0, bounds.width - 2 * margin), height: nil))
        let x = min(max(bounds.minX + anchor.midX - size.width / 2, bounds.minX + margin), bounds.maxX - size.width - margin)
        let below = bounds.minY + anchor.maxY + margin
        let y = below + size.height <= bounds.maxY - margin
            ? below
            : max(bounds.minY + margin, bounds.minY + anchor.minY - size.height - margin)
        tooltip.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}
