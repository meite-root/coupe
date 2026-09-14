import SwiftUI
import UIKit

struct SelectionControl: View {
    let state: SelectionState, currentTime: Double, mode: EditorMode
    let begin: () -> Void, drag: (CGSize, CGFloat) -> Void, release: () -> Void, stop: () -> Void
    @State private var didBeginGesture = false
    @State private var translation: CGSize = .zero

    var body: some View {
        VStack(spacing: 12) {
            if let start = state.startTime {
                HStack { Text("Start \(TimeFormatter.string(start))"); Spacer(); Text("Now \(TimeFormatter.string(currentTime))"); Spacer(); Text("Selected \(TimeFormatter.string(max(0, currentTime-start)))") }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let buttonSize: CGFloat = 82, threshold = max(60, geometry.size.width - buttonSize - 76)
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.18)).frame(height: 6).padding(.horizontal, buttonSize / 2)
                    HStack { Spacer(); Image(systemName: state.isLocked ? "lock.fill" : "lock.open").font(.title2).frame(width: 52, height: 52).background(.thinMaterial, in: Circle()).scaleEffect(lockScale(threshold)) }
                    Circle().fill(buttonColor).overlay {
                        Image(systemName: state.isLocked ? "stop.fill" : mode == .extract ? "scissors" : "text.bubble.fill")
                            .font(.title.bold()).foregroundStyle(.white)
                    }.frame(width: buttonSize, height: buttonSize).offset(x: state.isLocked ? threshold : min(max(0, translation.width), threshold))
                        .shadow(color: buttonColor.opacity(0.4), radius: 10)
                        .onTapGesture { if state.isLocked { stop() } }
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                guard !state.isLocked else { return }
                                if !didBeginGesture { didBeginGesture = true; begin() }
                                translation = value.translation; drag(value.translation, threshold)
                            }.onEnded { _ in
                                if didBeginGesture { release() }; didBeginGesture = false; translation = .zero
                            })
                }
            }.frame(height: 86)
            Text(instruction).font(.subheadline).foregroundStyle(.secondary)
                .accessibilityLabel(instruction)
            Button(state.isLocked ? "Stop locked selection" : "Start locked selection") {
                state.isLocked ? stop() : beginAccessibleLocked()
            }.buttonStyle(.bordered).accessibilityHint("Alternative to the hold and slide gesture")
        }.animation(.spring(response: 0.3), value: state).accessibilityElement(children: .contain)
    }
    private var buttonColor: Color {
        switch state {
        case .pressing: mode == .extract ? .orange : .indigo
        case .locked: mode == .extract ? .red : .purple
        case .finalizing: .blue
        case .failed: .red
        case .idle: mode == .extract ? .accentColor : .indigo
        }
    }
    private var instruction: String {
        switch state {
        case .idle: mode == .extract ? "Hold to extract • Slide right to lock" : "Hold to annotate • Slide right to lock"
        case .pressing: "Keep holding or slide toward the lock"
        case .locked: "Locked • Tap stop when finished"
        case .finalizing: mode == .extract ? "Creating clip…" : "Creating annotation…"
        case .failed(let message): message
        }
    }
    private func lockScale(_ threshold: CGFloat) -> CGFloat { 1 + 0.25 * min(1, max(0, translation.width / threshold)) }
    private func beginAccessibleLocked() { begin(); drag(CGSize(width: 10_000, height: 0), 1) }
}

private extension SelectionState {
    var isLocked: Bool { if case .locked = self { true } else { false } }
}
