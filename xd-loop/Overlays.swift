import SwiftUI
import AppKit

// Things drawn on top of whichever pattern is showing

// An away message scrolling right to left across a dark band in the lower third of the screen.
// Each time one has gone all the way past, another is picked at random
struct AwayBanner: View {
    private let state = AppState.shared
    @State private var message = ""
    @State private var started = Date()

    var body: some View {
        GeometryReader { geo in
            let size = max(36, geo.size.height * 0.11)
            let textWidth = (message as NSString).size(withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)]).width
            let distance = geo.size.width + textWidth

            TimelineView(.animation(paused: state.displayAsleep)) { timeline in
                let progress = timeline.date.timeIntervalSince(started) * state.awaySpeed / distance
                Text(message)
                    .font(.system(size: size, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: geo.size.width + textWidth / 2 - progress * distance, y: size * 0.8)
                    .frame(width: geo.size.width, height: size * 1.6)
                    .background(.black.opacity(0.75))
                    .clipped()
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.75)
                    .onChange(of: progress >= 1) { _, finished in
                        if finished { next() }
                    }
            }
        }
        .allowsHitTesting(false)
        .onAppear { next() }
    }

    // Another message at random, never the same one twice in a row
    private func next() {
        let others = state.awayMessages.filter { $0 != message }
        message = others.randomElement() ?? state.awayMessages.first ?? ""
        started = Date()
    }
}
