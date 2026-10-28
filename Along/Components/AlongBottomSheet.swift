import SwiftUI

enum SheetDetent: CaseIterable { case collapsed, half, full }

/// A persistent, draggable bottom sheet that sits above the tab bar while the map stays interactive.
/// Native `.sheet` can't coexist with other sheets on the same screen, so this is a small custom control.
struct AlongBottomSheet<Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    /// Reports the sheet's current visible height so floating map controls can sit above it.
    @Binding var visibleHeight: CGFloat
    var collapsedHeight: CGFloat = 96
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @GestureState private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let maxH = geo.size.height - 8
            let height = clamp(base(detent, maxH) - dragOffset, collapsedHeight, maxH)
            VStack(spacing: 0) {
                VStack(spacing: AlongSpacing.xs) {
                    Capsule().fill(AlongColor.border).frame(width: 36, height: 5).padding(.top, 8)
                    header()
                        .padding(.horizontal, AlongSpacing.gutter)
                        .padding(.bottom, AlongSpacing.sm)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($dragOffset) { value, state, _ in state = -value.translation.height }
                        .onEnded { value in settle(from: height, predicted: base(detent, maxH) - value.predictedEndTranslation.height, maxH: maxH) }
                )
                .onTapGesture { toggle() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(detent == .collapsed ? "Expands the list of plans" : "Collapses the list")
                .accessibilityAction { toggle() }

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(height > collapsedHeight + 30 ? 1 : 0)
            }
            .frame(height: height, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: AlongRadius.sheet, topTrailingRadius: AlongRadius.sheet, style: .continuous)
                    .fill(AlongColor.offWhite)
                    .shadow(color: .black.opacity(0.10), radius: 12, y: -2)
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: AlongRadius.sheet, topTrailingRadius: AlongRadius.sheet, style: .continuous))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .animation(reduceMotion || dragOffset != 0 ? nil : .smooth(duration: 0.35), value: detent)
            .onChange(of: height, initial: true) { _, new in visibleHeight = new }
        }
    }

    private func base(_ d: SheetDetent, _ maxH: CGFloat) -> CGFloat {
        switch d {
        case .collapsed: collapsedHeight
        case .half: maxH * 0.5
        case .full: maxH
        }
    }

    private func settle(from current: CGFloat, predicted: CGFloat, maxH: CGFloat) {
        let target = SheetDetent.allCases.min { abs(base($0, maxH) - predicted) < abs(base($1, maxH) - predicted) } ?? detent
        if target != detent { Haptics.soft() }
        detent = target
    }

    private func toggle() {
        Haptics.soft()
        detent = detent == .collapsed ? .half : .collapsed
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}
