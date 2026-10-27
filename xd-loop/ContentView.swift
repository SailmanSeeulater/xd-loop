import SwiftUI
import AppKit
import CoreText
import QuartzCore

// Shader time counts from when the app launched
let launchDate = Date()

// A GPU pattern: its display name and the function name in Shaders.metal
struct ShaderPattern {
    let name: String
    let function: String
}

// The order ` cycles through them in shader mode
let shaderPatterns = [
    ShaderPattern(name: "Plasma", function: "plasma"),
    ShaderPattern(name: "Ripples", function: "ripples"),
    ShaderPattern(name: "Ocean waves", function: "ocean"),
    ShaderPattern(name: "Spiral", function: "spiral"),
    ShaderPattern(name: "Checkerboard", function: "checkerboard"),
    ShaderPattern(name: "Lava lamp", function: "lavaLamp"),
    ShaderPattern(name: "Infinite tunnel", function: "tunnel"),
    ShaderPattern(name: "Black hole", function: "blackHole"),
    ShaderPattern(name: "Kaleidoscope", function: "kaleidoscope"),
]

// Shared by every screen, so switching or picking a colour on one changes them all.
// The keys in MyApp.swift change these. Anything with a didSet that saves is remembered
// between launches, so the app reopens the way you left it
@Observable
final class AppState {
    static let shared = AppState()
    static let asciiCount = allPatterns().count
    private let saved = UserDefaults.standard

    var shaderMode: Bool { didSet { saved.set(shaderMode, forKey: "shaderMode") } }
    var shaderIndex: Int { didSet { saved.set(shaderIndex, forKey: "shaderIndex") } }
    var asciiIndex: Int { didSet { saved.set(asciiIndex, forKey: "asciiIndex") } }
    var labelUntil = Date().addingTimeInterval(3)

    // The colour wheel: hue goes 0...1 around the wheel, amount is 0 (original colours) at the centre
    // to 1 (fully recoloured) at the edge
    var tintHue: Double { didSet { saved.set(tintHue, forKey: "tintHue") } }
    var tintAmount: Double { didSet { saved.set(tintAmount, forKey: "tintAmount") } }

    // On battery or in Low Power Mode, animations drop to 30 fps (AppDelegate keeps this up to date)
    var onBattery = false

    // While the display is off (or the Mac is asleep) nothing is drawn (IdleController keeps this up to date)
    var displayAsleep = false

    // Away messages: one at a time scrolls across the cover, picked at random (edited from the menu bar)
    static let defaultMessages = ["XD rawrrr", "why you looking?", "I'll be back", "?", "??", "???",
                                  "My name is Mr. Big Balls"]
    var awayEnabled: Bool { didSet { saved.set(awayEnabled, forKey: "awayEnabled") } }
    var awayMessages: [String] { didSet { saved.set(awayMessages, forKey: "awayMessages") } }
    var awaySpeed: Double { didSet { saved.set(awaySpeed, forKey: "awaySpeed") } }   // points per second

    // While covering, jump to a random pattern every this many seconds (0 = off)
    var autoCycle: Double { didSet { saved.set(autoCycle, forKey: "autoCycle") } }

    // How strongly patterns react to sound from the microphone (0 = off, up to 2.6 = wild)
    var audioStrength: Double { didSet { saved.set(audioStrength, forKey: "audioStrength") } }

    // The microphone's beat level scaled by the strength setting; 0 when audio reaction is off
    var audioPulse: Double { audioStrength > 0 ? AudioMeter.shared.level * audioStrength : 0 }

    private init() {
        shaderMode = saved.bool(forKey: "shaderMode")
        shaderIndex = min(max(0, saved.integer(forKey: "shaderIndex")), shaderPatterns.count - 1)
        asciiIndex = min(max(0, saved.integer(forKey: "asciiIndex")), Self.asciiCount - 1)
        tintHue = saved.double(forKey: "tintHue")
        tintAmount = saved.double(forKey: "tintAmount")
        awayEnabled = saved.object(forKey: "awayEnabled") as? Bool ?? true
        awayMessages = saved.stringArray(forKey: "awayMessages") ?? Self.defaultMessages
        awaySpeed = saved.object(forKey: "awaySpeed") as? Double ?? 220
        autoCycle = saved.double(forKey: "autoCycle")
        audioStrength = saved.double(forKey: "audioStrength")
    }

    var wheelOpen = false {
        didSet {
            // Show the mouse pointer only while the wheel is open
            guard wheelOpen != oldValue else { return }
            if wheelOpen { NSCursor.unhide() } else { NSCursor.hide() }
        }
    }

    var tintColor: Color { Color(hue: tintHue, saturation: 1, brightness: 1) }

    func toggleMode() {
        shaderMode.toggle()
        wheelOpen = false
        labelUntil = Date().addingTimeInterval(2)
    }

    // step is +1 for the next one, -1 for the previous one; both wrap around
    func stepShader(_ step: Int) {
        shaderIndex = (shaderIndex + step + shaderPatterns.count) % shaderPatterns.count
        labelUntil = Date().addingTimeInterval(2)
    }

    // Each AsciiView notices the change and switches (and shows its own label)
    func stepAscii(_ step: Int) {
        asciiIndex = (asciiIndex + step + Self.asciiCount) % Self.asciiCount
    }

    // Auto-cycle: a different pattern at random, in whichever mode is showing
    func randomPattern() {
        if shaderMode {
            shaderIndex = Self.randomOther(than: shaderIndex, in: shaderPatterns.count)
        } else {
            asciiIndex = Self.randomOther(than: asciiIndex, in: Self.asciiCount)
        }
    }

    private static func randomOther(than current: Int, in count: Int) -> Int {
        guard count > 1 else { return 0 }
        let pick = Int.random(in: 0..<count - 1)
        return pick >= current ? pick + 1 : pick
    }
}

struct ContentView: View {
    private let state = AppState.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            AsciiRepresentable(paused: state.shaderMode)
            if state.shaderMode {
                ShaderView(pattern: shaderPatterns[state.shaderIndex])
            }
            if state.awayEnabled && !state.awayMessages.isEmpty {
                AwayBanner()
            }
            if state.shaderMode {
                TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                    if timeline.date < state.labelUntil { label }
                }
                if state.wheelOpen {
                    ColorWheel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // Shows the shader's name for a moment after switching
    private var label: some View {
        Text(" Shader \(state.shaderIndex + 1)/\(shaderPatterns.count)  \(shaderPatterns[state.shaderIndex].name)    ` next · ⇧` back · = colours · Tab ASCII ")
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .background(.black)
            .padding(.leading, 24)
            .padding(.top, 30)
    }
}

// Runs one of the GPU shaders from Shaders.metal over the whole screen,
// then recolours it with the colour wheel's choice
struct ShaderView: View {
    let pattern: ShaderPattern
    private let state = AppState.shared

    var body: some View {
        // As fast as the screen refreshes, or 30 fps on battery; stopped while the display is off
        TimelineView(.animation(minimumInterval: state.onBattery ? 1.0 / 30 : nil, paused: state.displayAsleep)) { timeline in
            let t = timeline.date.timeIntervalSince(launchDate)
            let pulse = state.audioPulse
            GeometryReader { geo in
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderFunction(library: .default, name: pattern.function)(
                        .float(t), .float2(geo.size)))
                    .colorEffect(ShaderLibrary.tint(.color(state.tintColor), .float(state.tintAmount), .float(pulse)))
                    // A little zoom "thump" on loud moments
                    .scaleEffect(1 + pulse * 0.05)
            }
        }
    }
}

// Press = in shader mode to open. Drag around it to pick a colour; the centre means original colours
struct ColorWheel: View {
    private let state = AppState.shared
    private let diameter: CGFloat = 280

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Every hue around the edge, fading to white in the middle
                Circle()
                    .fill(AngularGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) },
                                          center: .center))
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: diameter / 2))
                // Marks the picked colour
                Circle()
                    .fill(state.tintAmount > 0 ? state.tintColor : .white)
                    .overlay(Circle().stroke(.black, lineWidth: 3))
                    .frame(width: 24, height: 24)
                    .position(markerPosition)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { pick($0.location) })

            Button("Original colours") { state.tintAmount = 0 }

            Text("drag to pick · edge = strong, centre = none · = to close")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(28)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
    }

    private var markerPosition: CGPoint {
        let r = diameter / 2
        let angle = state.tintHue * 2 * .pi
        return CGPoint(x: r + cos(angle) * r * state.tintAmount,
                       y: r + sin(angle) * r * state.tintAmount)
    }

    // The angle from the centre picks the hue, the distance picks how strong it is
    private func pick(_ point: CGPoint) {
        let r = diameter / 2
        let dx = point.x - r, dy = point.y - r
        var angle = atan2(dy, dx) / (2 * .pi)
        if angle < 0 { angle += 1 }
        state.tintHue = angle
        state.tintAmount = min(1, (dx * dx + dy * dy).squareRoot() / r)
    }
}

// Lets SwiftUI show our AppKit AsciiView
struct AsciiRepresentable: NSViewRepresentable {
    let paused: Bool

    func makeNSView(context: Context) -> AsciiView { AsciiView(frame: .zero) }
    func updateNSView(_ nsView: AsciiView, context: Context) { nsView.isPaused = paused }
}

// Draws whichever pattern is active; the patterns themselves live in Patterns.swift
final class AsciiView: NSView {
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // Paused while shader mode is on top; shows the label again when coming back
    var isPaused = false {
        didSet {
            if oldValue && !isPaused { labelUntil = CACurrentMediaTime() + 2 }
        }
    }

    private let patterns = allPatterns()
    private var current = AppState.shared.asciiIndex
    private var onBattery: Bool?
    private var grid = Grid()
    private var patternTime = 0.0
    private var lastFrame = CACurrentMediaTime()
    private var labelUntil: CFTimeInterval = 0

    private var cellW: CGFloat = 0
    private var cellH: CGFloat = 0
    // For each of the pattern's characters: its glyph and which colour bucket it's drawn in
    private var glyphOf: [CGGlyph] = []
    private var bucketOf: [Int] = []
    private var bucketColors: [CGColor] = []
    // Filled every frame: the glyphs and positions to draw in each colour
    private var bucketGlyphs: [[CGGlyph]] = []
    private var bucketPositions: [[CGPoint]] = []
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cellW = ("M" as NSString).size(withAttributes: [.font: font]).width
        cellH = ceil(font.ascender - font.descender + font.leading)
        loadPattern()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { true }

    // Start a timer synced to the screen's refresh rate once we're on screen,
    // and stop it when our window closes (e.g. a monitor was unplugged)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            link?.invalidate()
            link = nil
            return
        }
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        defer { lastFrame = now }
        guard !isPaused, !AppState.shared.displayAsleep else { return }
        let state = AppState.shared

        // 60 fps when plugged in, 30 on battery
        if onBattery != state.onBattery {
            onBattery = state.onBattery
            link.preferredFrameRateRange = state.onBattery
                ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }

        // ` was pressed (see MyApp.swift)
        let wanted = state.asciiIndex % patterns.count
        if wanted != current {
            current = wanted
            grid.clear()
            labelUntil = CACurrentMediaTime() + 2
            loadPattern()
        }

        let cols = Int(bounds.width / cellW) + 1
        let rows = Int(bounds.height / cellH) + 1
        if cols != grid.cols || rows != grid.rows {
            grid.resize(cols: cols, rows: rows)
        }
        // Loud moments speed time up and make field patterns denser
        let pulse = state.audioPulse
        audioPulse = pulse
        patternTime += (now - lastFrame) * (1 + pulse * 1.5)
        patterns[current].update(&grid, t: patternTime)
        needsDisplay = true
    }

    // Look up the glyph and colour for each of the active pattern's characters once,
    // so drawing doesn't have to. Characters that share a colour share a bucket
    private func loadPattern() {
        let pattern = patterns[current]
        let utf16 = pattern.chars.map { $0.utf16.first! }
        glyphOf = [CGGlyph](repeating: 0, count: utf16.count)
        CTFontGetGlyphsForCharacters(font as CTFont, utf16, &glyphOf, utf16.count)

        bucketColors = []
        bucketOf = pattern.chars.indices.map { i in
            let color = pattern.color(i)
            if let existing = bucketColors.firstIndex(of: color) { return existing }
            bucketColors.append(color)
            return bucketColors.count - 1
        }
        bucketGlyphs = Array(repeating: [], count: bucketColors.count)
        bucketPositions = Array(repeating: [], count: bucketColors.count)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(.black)
        ctx.fill(bounds)
        ctx.textMatrix = .identity

        // Sort every visible cell into a bucket by colour
        for b in bucketColors.indices {
            bucketGlyphs[b].removeAll(keepingCapacity: true)
            bucketPositions[b].removeAll(keepingCapacity: true)
        }
        let baseline = -font.descender
        for y in 0..<grid.rows {
            let py = CGFloat(grid.rows - 1 - y) * cellH + baseline
            for x in 0..<grid.cols {
                let c = Int(grid.cells[y * grid.cols + x])
                if c == 0 || c >= bucketOf.count { continue }
                let b = bucketOf[c]
                bucketGlyphs[b].append(glyphOf[c])
                bucketPositions[b].append(CGPoint(x: CGFloat(x) * cellW, y: py))
            }
        }

        // Then draw each colour in one go
        for b in bucketColors.indices where !bucketPositions[b].isEmpty {
            ctx.setFillColor(bucketColors[b])
            CTFontDrawGlyphs(font as CTFont, bucketGlyphs[b], bucketPositions[b], bucketPositions[b].count, ctx)
        }

        if CACurrentMediaTime() < labelUntil { drawLabel() }
    }

    // Shows the pattern's name for a moment after switching
    private func drawLabel() {
        let text = " \(current + 1)/\(patterns.count)  \(patterns[current].name)    ` next · ⇧` back · Tab shaders " as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black,
        ]
        text.draw(at: NSPoint(x: 24, y: bounds.height - 48), withAttributes: attrs)
    }
}

#Preview {
    ContentView()
        .frame(width: 600, height: 400)
}
