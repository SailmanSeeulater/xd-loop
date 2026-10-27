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

// Coloured ASCII sparks that burst out wherever the mouse moves while the cover is up
struct MouseTrail: View {
    let screenFrame: CGRect
    private let state = AppState.shared
    @State private var sparks = SparkField()

    var body: some View {
        TimelineView(.animation(paused: state.displayAsleep)) { timeline in
            Canvas { context, _ in
                let now = timeline.date.timeIntervalSinceReferenceDate
                sparks.step(now: now, mouse: localMouse())
                for spark in sparks.sparks {
                    let fade = 1 - (now - spark.born) / SparkField.lifetime
                    let text = Text(spark.char)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hue: spark.hue, saturation: 0.7, brightness: 1).opacity(fade))
                    context.draw(text, at: spark.position)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // The pointer in this screen's coordinates, or nil when it's on another screen
    private func localMouse() -> CGPoint? {
        let mouse = NSEvent.mouseLocation
        guard screenFrame.contains(mouse) else { return nil }
        return CGPoint(x: mouse.x - screenFrame.minX, y: screenFrame.maxY - mouse.y)
    }
}

// The sparks themselves: spawned along the mouse's path, flying outwards, falling a little, fading out
final class SparkField {
    struct Spark {
        var position: CGPoint
        var velocity: CGVector
        let born: Double
        let char: String
        let hue: Double
    }

    static let lifetime = 1.2
    private static let chars = ["*", "+", ".", "o", "x", "·"]
    private(set) var sparks: [Spark] = []
    private var lastMouse: CGPoint?
    private var lastStep = 0.0

    func step(now: Double, mouse: CGPoint?) {
        let dt = lastStep == 0 ? 0 : min(0.1, now - lastStep)
        lastStep = now

        sparks.removeAll { now - $0.born > Self.lifetime }
        for i in sparks.indices {
            sparks[i].position.x += sparks[i].velocity.dx * dt
            sparks[i].position.y += sparks[i].velocity.dy * dt
            sparks[i].velocity.dy += 140 * dt   // a little gravity
        }

        // More sparks the further the mouse moved, spread along the path it took
        if let mouse, let last = lastMouse {
            let dx = mouse.x - last.x, dy = mouse.y - last.y
            let count = min(8, Int((dx * dx + dy * dy).squareRoot() / 6))
            for k in 0..<count {
                let f = CGFloat(k) / CGFloat(count)
                let angle = Double.random(in: 0..<2 * .pi)
                let speed = Double.random(in: 30...160)
                sparks.append(Spark(position: CGPoint(x: last.x + dx * f, y: last.y + dy * f),
                                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                    born: now,
                                    char: Self.chars.randomElement()!,
                                    hue: (now * 0.15).truncatingRemainder(dividingBy: 1)))
            }
        }
        lastMouse = mouse
        if sparks.count > 400 { sparks.removeFirst(sparks.count - 400) }
    }
}
