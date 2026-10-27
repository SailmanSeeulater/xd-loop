import Foundation
import CoreGraphics

// MARK: - Building blocks

// The screen as a grid of character slots. Each cell holds an index into
// the active pattern's chars, where 0 means blank
struct Grid {
    var cols = 0
    var rows = 0
    var cells: [UInt16] = []

    mutating func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = Array(repeating: 0, count: cols * rows)
    }

    mutating func clear() {
        for i in cells.indices { cells[i] = 0 }
    }

    // Sets one cell, ignoring anything off-screen
    mutating func set(_ x: Int, _ y: Int, _ value: UInt16) {
        guard x >= 0, x < cols, y >= 0, y < rows else { return }
        cells[y * cols + x] = value
    }
}

protocol Pattern: AnyObject {
    var name: String { get }
    var chars: [Character] { get }   // the first one should be a space
    func color(_ index: Int) -> CGColor
    func update(_ grid: inout Grid, t: Double)
    func activate()     // the pattern just came on screen
    func deactivate()   // the pattern just left the screen
}

// Most patterns don't care when they come and go
extension Pattern {
    func activate() {}
    func deactivate() {}
}

// How many units fit across the screen; bigger = smaller, more repeated shapes
let span = 32.0

// Dark → bright
let ramp = " .:-=+*#%@"

// The microphone beat level (0 = silent), set by AsciiView every frame. Field patterns get denser on loud moments
var audioPulse = 0.0

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: 1)
}

// Turns a brightness from 0...1 into a character index
func level(_ v: Double, _ count: Int) -> UInt16 {
    let i = v * Double(count)
    if !(i > 0) { return 0 }
    if i >= Double(count - 1) { return UInt16(count - 1) }
    return UInt16(i)
}

// A repeatable "random" number in 0..<1 for any input
func hash(_ n: Double) -> Double {
    let s = sin(n * 127.1 + 311.7) * 43758.5453
    return s - floor(s)
}

// Where a cell is, measured from the centre of the screen
struct Spot {
    let x: Double, y: Double        // y grows downward
    let d: Double, a: Double        // distance and angle from the centre (cells are ~2x tall, so y counts double)
    let t: Double                   // seconds since start
    let halfW: Double, halfH: Double
}

// A pattern where each cell's brightness is worked out from its position and the time
final class FieldPattern: Pattern {
    let name: String
    let chars: [Character]
    let tint: CGColor
    let value: (Spot) -> Double

    init(_ name: String, chars: String = ramp, color: CGColor, value: @escaping (Spot) -> Double) {
        self.name = name
        self.chars = Array(chars)
        self.tint = color
        self.value = value
    }

    func color(_ index: Int) -> CGColor { tint }

    func update(_ grid: inout Grid, t: Double) {
        let k = span / Double(grid.cols)
        let halfW = Double(grid.cols) * k / 2
        let halfH = Double(grid.rows) * k / 2
        let n = chars.count
        for row in 0..<grid.rows {
            let y = Double(row) * k - halfH
            for col in 0..<grid.cols {
                let x = Double(col) * k - halfW
                let spot = Spot(x: x, y: y, d: (x * x + 4 * y * y).squareRoot(), a: atan2(2 * y, x),
                                t: t, halfW: halfW, halfH: halfH)
                grid.cells[row * grid.cols + col] = level(value(spot) + audioPulse * 0.35, n)
            }
        }
    }
}

// MARK: - The playlist

// All 15 patterns, in the order the ` key cycles through them
func allPatterns() -> [Pattern] {
    var list: [Pattern] = []

    // 1. Three overlapping sine waves
    list.append(FieldPattern("Plasma", color: rgb(0.22, 1, 0.42)) { p in
        (sin(p.x * 0.15 + p.t) + sin(p.y * 0.3 - p.t) + sin((p.x + p.y) * 0.1 + p.t * 0.5) + 3) / 6
    })

    // 2. Rings spreading out from the centre
    list.append(FieldPattern("Ripples", color: rgb(0.35, 0.84, 1)) { p in
        (sin(p.d * 0.6 - p.t * 3) + 1) / 2
    })

    list.append(MatrixRain())
    list.append(Starfield())

    // 5. A wavy surface line with water below it
    list.append(FieldPattern("Ocean waves", chars: " .-~", color: rgb(0.31, 0.72, 1)) { p in
        let surface = p.halfH * 2 * 0.45 + sin(p.x * 0.2 + p.t * 2) * 2 + sin(p.x * 0.07 - p.t) * 1.5
        let depth = (p.y + p.halfH) - surface
        if depth < 0 { return 0 }
        if depth < 1 { return 1 }
        if depth < 3 { return 0.6 }
        return 0.3
    })

    list.append(DoomFire())

    // 7. Angle and distance mixed together make arms that rotate
    list.append(FieldPattern("Spiral", color: rgb(0.77, 0.55, 1)) { p in
        (sin(p.a * 3 + p.d * 0.4 - p.t * 3) + 1) / 2
    })

    list.append(Snowfall())

    // 9. Rotate the coordinates, then alternate tiles
    list.append(FieldPattern("Checkerboard", chars: " #", color: rgb(1, 0.85, 0.29)) { p in
        let c = cos(p.t * 0.5), s = sin(p.t * 0.5)
        let size = 3 + sin(p.t) * 1.5
        let u = p.x * c - p.y * 2 * s
        let v = p.x * s + p.y * 2 * c
        return (Int(floor(u / size)) + Int(floor(v / size))) & 1 == 1 ? 1 : 0
    })

    // 10. Four moving blobs; where their pull adds up, they merge
    list.append(FieldPattern("Lava lamp", chars: " .+#@", color: rgb(1, 0.35, 0.48)) { p in
        var sum = 0.0
        for i in 0..<4 {
            let f = Double(i)
            let bx = sin(p.t * (0.5 + f * 0.2) + f * 2) * p.halfW * 0.7
            let by = cos(p.t * (0.4 + f * 0.15) + f) * p.halfH * 0.7
            let dx = p.x - bx, dy = (p.y - by) * 2
            sum += 12 / (dx * dx + dy * dy + 0.1)
        }
        if sum > 1 { return 1 }
        if sum > 0.7 { return 0.75 }
        if sum > 0.5 { return 0.5 }
        if sum > 0.35 { return 0.25 }
        return 0
    })

    list.append(Donut())

    // 12. 1/distance gives depth, angle gives the walls, time moves us forward
    list.append(FieldPattern("Infinite tunnel", color: rgb(0.35, 1, 0.82)) { p in
        let depth = 8 / (p.d + 0.01) + p.t * 2
        let around = p.a / .pi * 4 + p.t * 0.5
        let stripe = (Int(floor(depth)) + Int(floor(around))) & 1
        return stripe == 1 ? min(1, p.d / p.halfW) : 0
    })

    // 13. A swirl that twists harder the closer it gets to the dark centre
    list.append(FieldPattern("Black hole", color: rgb(0.72, 0.55, 1)) { p in
        if p.d < 3 { return 0 }
        if p.d < 4 { return 1 }
        let swirl = p.a + 6 / (p.d + 1) + p.t * 2
        return (sin(swirl * 3 + p.d * 0.3) + 1) / 2 * min(1, p.d / 6)
    })

    list.append(GlitchStorm())

    // 15. Fold the angle into 8 mirrored slices, then draw plasma in them
    list.append(FieldPattern("Kaleidoscope", color: rgb(1, 0.48, 0.88)) { p in
        let seg = Double.pi / 4
        let m = (p.a.truncatingRemainder(dividingBy: 2 * seg) + 2 * seg).truncatingRemainder(dividingBy: 2 * seg)
        let a = abs(m - seg) + p.t * 0.3
        let x = cos(a) * p.d * 0.3, y = sin(a) * p.d * 0.3
        return (sin(x + p.t) + sin(y * 1.3 - p.t) + sin((x + y) * 0.7 + p.t * 0.7) + 3) / 6
    })

    // 16-20: terminal classics
    list.append(Life())
    list.append(HexDump())
    list.append(Maze())
    list.append(Pipes())
    list.append(BigClock())

    // 21-30: developer screens (DevPatterns.swift)
    list += developerPatterns()

    return list
}

// MARK: - Patterns that need more than a formula

// 3. Each column has its own falling stream; the head is white, the trail green
final class MatrixRain: Pattern {
    let name = "Matrix rain"
    static let symbols = Array("01ABCDEFXYZ$#@%&")
    // Space, then the symbols twice: first copy for the trail, second for the head
    let chars: [Character] = [" "] + MatrixRain.symbols + MatrixRain.symbols
    let green = rgb(0.22, 1, 0.42)
    let white = rgb(0.9, 1, 0.9)

    func color(_ index: Int) -> CGColor { index > Self.symbols.count ? white : green }

    func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let n = Self.symbols.count
        let trail = max(8, grid.rows / 4)
        let tick = floor(t * 10)
        for x in 0..<grid.cols {
            let fx = Double(x)
            let speed = (0.6 + hash(fx) * 1.2) * Double(grid.rows) * 0.45
            let head = Int((t * speed + hash(fx + 7) * 500).truncatingRemainder(dividingBy: Double(grid.rows + trail)))
            for i in 0..<trail {
                let y = head - i
                let pick = min(n - 1, Int(hash(fx * 31 + Double(y) * 17 + tick) * Double(n)))
                grid.set(x, y, UInt16(1 + pick + (i == 0 ? n : 0)))
            }
        }
    }
}

// 4. Stars fly outward from the centre, getting brighter as they get closer
final class Starfield: Pattern {
    let name = "Starfield"
    let chars: [Character] = Array(" .+*")
    let white = rgb(1, 1, 1)

    func color(_ index: Int) -> CGColor { white }

    func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let cx = Double(grid.cols) / 2, cy = Double(grid.rows) / 2
        let count = grid.cols * grid.rows / 20
        for i in 0..<count {
            let f = Double(i)
            let angle = hash(f) * .pi * 2
            let z = (t * 0.3 + hash(f + 100)).truncatingRemainder(dividingBy: 1)
            let r = z * z * Double(grid.cols) * 0.7
            let x = Int(cx + cos(angle) * r), y = Int(cy + sin(angle) * r / 2)
            grid.set(x, y, z < 0.3 ? 1 : z < 0.65 ? 2 : 3)
        }
    }
}

// 6. The Doom fire: every cell passes its heat to the row above, losing a bit on the way
final class DoomFire: Pattern {
    let name = "Doom fire"
    let chars: [Character] = Array(" .,:;-=+*#%@")
    let maxHeat = 36
    let cooling: UInt32 = 2   // 1 = tall fire, 2 = medium, 3 = short

    private var colors: [CGColor] = []
    private var heat: [Int] = []
    private var cols = 0
    private var rows = 0
    private var seed: UInt32 = 2463534242

    init() {
        // Black → red → yellow → white
        colors = (0..<chars.count).map { i in
            let f = CGFloat(i) / CGFloat(chars.count - 1)
            return rgb(min(1, f * 3), max(0, min(1, f * 3 - 1)), max(0, min(1, f * 3 - 2)))
        }
    }

    func color(_ index: Int) -> CGColor { colors[index] }

    func update(_ grid: inout Grid, t: Double) {
        if grid.cols != cols || grid.rows != rows { reset(cols: grid.cols, rows: grid.rows) }
        step()
        let top = chars.count - 1
        for i in heat.indices { grid.cells[i] = UInt16(heat[i] * top / maxHeat) }
    }

    // Start over with the bottom row on fire
    private func reset(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        heat = Array(repeating: 0, count: cols * rows)
        for x in 0..<cols { heat[(rows - 1) * cols + x] = maxHeat }
    }

    // Fast random numbers (xorshift); much quicker than Int.random for this many cells
    private func random() -> UInt32 {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return seed
    }

    private func step() {
        guard rows > 1 else { return }
        for x in 0..<cols {
            for y in 1..<rows {
                let src = y * cols + x
                let r = random()
                let dst = src - cols - Int(r & 3) + 1
                guard dst >= 0 && dst < heat.count else { continue }
                heat[dst] = max(heat[src] - Int((r >> 2) % (cooling + 1)), 0)
            }
        }
    }
}

// 8. Flakes drift down and sway side to side
final class Snowfall: Pattern {
    let name = "Snowfall"
    let chars: [Character] = Array(" .*")
    let snow = rgb(0.91, 0.96, 1)

    func color(_ index: Int) -> CGColor { snow }

    func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let w = Double(grid.cols), h = Double(grid.rows)
        let count = grid.cols * grid.rows / 12
        for i in 0..<count {
            let f = Double(i)
            let x = (hash(f) * w + sin(t + f) * 1.5 + w).truncatingRemainder(dividingBy: w)
            let y = (t * (0.5 + hash(f + 3)) * h * 0.2 + hash(f + 9) * h).truncatingRemainder(dividingBy: h)
            grid.set(Int(x), Int(y), hash(f + 5) > 0.5 ? 2 : 1)
        }
    }
}

// 11. A 3D torus: spin points around a ring, project them to 2D, keep the nearest one per cell
final class Donut: Pattern {
    let name = "Spinning donut"
    let chars: [Character] = Array(" .,-~:;=!*#$@")

    private var colors: [CGColor] = []
    private var depth: [Double] = []
    // Sines and cosines around the tube (j) and around the ring (i), worked out once
    private let tube = stride(from: 0.0, to: 2 * .pi, by: 0.03).map { (sin($0), cos($0)) }
    private let ring = stride(from: 0.0, to: 2 * .pi, by: 0.01).map { (sin($0), cos($0)) }

    init() {
        // Dim orange → bright yellow, by how much light hits the surface
        colors = (0..<chars.count).map { i in
            let f = CGFloat(i) / CGFloat(chars.count - 1)
            return rgb(0.6 + 0.4 * f, 0.3 + 0.55 * f, 0.1 + 0.3 * f)
        }
    }

    func color(_ index: Int) -> CGColor { colors[index] }

    func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        if depth.count != grid.cells.count {
            depth = Array(repeating: 0, count: grid.cells.count)
        } else {
            for i in depth.indices { depth[i] = 0 }
        }
        let cx = Double(grid.cols) / 2, cy = Double(grid.rows) / 2
        // As big as fits; cells are about twice as tall as wide
        let sx = min(Double(grid.cols) * 0.375, Double(grid.rows) * 1.3)
        let sy = sx / 2
        let sinA = sin(t), cosA = cos(t), sinB = sin(t * 0.5), cosB = cos(t * 0.5)

        for (sinJ, cosJ) in tube {
            let h = cosJ + 2
            for (sinI, cosI) in ring {
                let D = 1 / (sinI * h * sinA + sinJ * cosA + 5)
                let tt = sinI * h * cosA - sinJ * sinA
                let x = Int(cx + sx * D * (cosI * h * cosB - tt * sinB))
                let y = Int(cy + sy * D * (cosI * h * sinB + tt * cosB))
                guard x >= 0, x < grid.cols, y >= 0, y < grid.rows else { continue }
                let idx = y * grid.cols + x
                guard D > depth[idx] else { continue }
                depth[idx] = D
                let light = 8 * ((sinJ * sinA - sinI * cosJ * cosA) * cosB
                                 - sinI * cosJ * sinA - sinJ * cosA - cosI * cosJ * sinB)
                grid.cells[idx] = UInt16(1 + max(0, min(11, Int(light))))
            }
        }
    }
}

// 14. Plasma underneath, torn rows, corrupted blocks, and a flashing warning
final class GlitchStorm: Pattern {
    let name = "Glitch storm"
    // 0-9: the brightness ramp, 10-18: glitch symbols, then the letters of the message
    let chars: [Character] = Array(" .:-=+*#%@!$&<>/\\|?SYTEMFAILUR")
    let red = rgb(1, 0.29, 0.29)
    let white = rgb(1, 1, 1)
    private var index: [Character: UInt16] = [:]

    init() {
        for (i, c) in chars.enumerated() { index[c] = UInt16(i) }
    }

    func color(_ index: Int) -> CGColor { index < 10 ? red : white }

    func update(_ grid: inout Grid, t: Double) {
        let k = span / Double(grid.cols)
        let frame = floor(t * 10)
        let blockW = max(6, grid.cols / 5), blockH = max(3, grid.rows / 5)

        for y in 0..<grid.rows {
            let fy = Double(y)
            // Some rows get torn sideways
            let torn = hash(frame + fy * 3) > 0.8
            let shift = torn ? Int((hash(frame * 7 + fy) - 0.5) * Double(grid.cols) * 0.4) : 0
            for x in 0..<grid.cols {
                let xx = x + shift
                let block = hash(frame + Double(xx / blockW) * 13 + Double(y / blockH) * 7)
                let value: UInt16
                if block > 0.88 {
                    value = UInt16(10 + Int(hash(frame + Double(x) * 5 + fy) * 9) % 9)
                } else {
                    let v = (sin(Double(xx) * k * 0.2 + t * 3) + sin(fy * k * 0.5 - t * 2) + 2) / 4
                    value = level(v, 10)
                }
                grid.cells[y * grid.cols + x] = value
            }
        }

        // Every couple of seconds, flash a message in the middle
        if Int(t * 1.5) % 3 == 0 {
            let msg = Array(" SYSTEM FAILURE ")
            let y = grid.rows / 2, start = grid.cols / 2 - msg.count / 2
            for (i, c) in msg.enumerated() { grid.set(start + i, y, index[c] ?? 0) }
        }
    }
}

// MARK: - Terminal classics

// Fast random numbers (xorshift), for patterns that need lots of them
struct FastRandom {
    var seed: UInt32

    mutating func next() -> UInt32 {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return seed
    }
}

// 16. Conway's Game of Life: a cell with 2-3 live neighbours survives, an empty one with exactly 3 is born.
// New cells are bright, old ones dimmer, and dead ones leave a faint trail
final class Life: Pattern {
    let name = "Game of Life"
    let chars: [Character] = Array(" .o@")
    private let colors = [rgb(0, 0, 0), rgb(0.1, 0.4, 0.15), rgb(0.2, 0.8, 0.35), rgb(0.6, 1, 0.65)]

    // > 0: alive for that many generations, < 0: dead for that many, 0: empty
    private var age: [Int] = []
    private var cols = 0
    private var rows = 0
    private var lastStep = 0.0
    private var generation = 0
    private var history: [Int] = []
    private var random = FastRandom(seed: 2463534242)

    func color(_ index: Int) -> CGColor { colors[index] }

    func update(_ grid: inout Grid, t: Double) {
        if grid.cols != cols || grid.rows != rows {
            cols = grid.cols
            rows = grid.rows
            reseed()
        }
        // 40 generations per second
        if t - lastStep >= 1.0 / 40 {
            lastStep = t
            step()
        }
        for i in age.indices {
            let a = age[i]
            grid.cells[i] = a > 3 ? 2 : a > 0 ? 3 : a < 0 && a > -4 ? 1 : 0
        }
    }

    // Fill about 40% of the cells at random
    private func reseed() {
        age = (0..<cols * rows).map { _ in random.next() % 10 < 4 ? 1 : 0 }
        generation = 0
        history = []
    }

    private func step() {
        var next = age
        var population = 0
        for y in 0..<rows {
            for x in 0..<cols {
                // Count live neighbours, wrapping around the screen edges
                var n = 0
                for dy in -1...1 {
                    let yy = (y + dy + rows) % rows
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let xx = (x + dx + cols) % cols
                        if age[yy * cols + xx] > 0 { n += 1 }
                    }
                }
                let i = y * cols + x
                let alive = age[i] > 0
                if alive && (n == 2 || n == 3) {
                    next[i] = min(age[i] + 1, 100)
                    population += 1
                } else if !alive && n == 3 {
                    next[i] = 1
                    population += 1
                } else if alive {
                    next[i] = -1
                } else if age[i] < 0 {
                    next[i] = max(age[i] - 1, -10)
                }
            }
        }
        age = next
        generation += 1

        // Start over once it has died out, settled down, or run for a minute
        history.append(population)
        if history.count > 30 { history.removeFirst() }
        let settled = history.count == 30 && history.max()! - history.min()! < 3
        if generation > 900 || population < cols * rows / 100 || settled { reseed() }
    }
}

// 17. Endless bytes scrolling past, like `xxd /dev/urandom`. Some lines are "text" so letters show up on the right
final class HexDump: Pattern {
    let name = "Hex dump"
    static let symbols = Array("0123456789abcdef|.ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    // Space, then the symbols twice: first copy dim, second copy bright
    let chars: [Character] = [" "] + HexDump.symbols + HexDump.symbols
    let dim = rgb(0.6, 0.38, 0.05)
    let bright = rgb(1, 0.72, 0.2)
    private var index: [Character: Int] = [:]
    private let hex = Array("0123456789abcdef")

    init() {
        for (i, c) in Self.symbols.enumerated() { index[c] = i }
    }

    func color(_ index: Int) -> CGColor { index > Self.symbols.count ? bright : dim }

    func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        // Each dump line is 77 characters; fit as many side by side as the screen allows
        let blockW = 80
        let blocks = max(1, (grid.cols + 3) / blockW)
        let firstLine = Int(t * 20)
        for b in 0..<blocks {
            for y in 0..<grid.rows {
                writeLine(firstLine + y + b * 7919, x: b * blockW, y: y, grid: &grid)
            }
        }
    }

    // One line: offset, 16 bytes in hex, then the same bytes as letters
    private func writeLine(_ line: Int, x: Int, y: Int, grid: inout Grid) {
        var col = x
        func put(_ c: Character, bright: Bool) {
            if let i = index[c] { grid.set(col, y, UInt16(1 + i + (bright ? Self.symbols.count : 0))) }
            col += 1
        }

        let offset = line * 16
        for shift in stride(from: 28, through: 0, by: -4) { put(hex[(offset >> shift) & 15], bright: false) }
        col += 2

        let isText = hash(Double(line) * 0.37) > 0.6
        var bytes: [Int] = []
        for j in 0..<16 {
            let h = hash(Double(offset + j))
            let byte = isText ? 65 + Int(h * 26) % 26 : Int(h * 256) % 256
            bytes.append(byte)
            put(hex[byte >> 4], bright: true)
            put(hex[byte & 15], bright: true)
            col += j == 7 ? 2 : 1
        }

        col += 1
        put("|", bright: false)
        for byte in bytes {
            put(byte >= 65 && byte <= 90 ? Character(UnicodeScalar(UInt8(byte))) : ".", bright: false)
        }
        put("|", bright: false)
    }
}

// 18. The famous one-line BASIC program 10 PRINT CHR$(205.5+RND(1)); : GOTO 10 —
// random / and \ typed out forever make a maze
final class Maze: Pattern {
    let name = "10 PRINT maze"
    let chars: [Character] = Array(" /\\")
    let blue = rgb(0.53, 0.53, 1)
    private var startT = 0.0
    private var lastSeen = -10.0

    func color(_ index: Int) -> CGColor { blue }

    func update(_ grid: inout Grid, t: Double) {
        // Start typing from scratch whenever we switch to this pattern
        if t - lastSeen > 0.5 { startT = t }
        lastSeen = t

        grid.clear()
        let typed = Int((t - startT) * Double(grid.cols) * 8)   // 8 lines per second
        let lastLine = typed / grid.cols
        let firstLine = max(0, lastLine - grid.rows + 1)
        for y in 0..<grid.rows {
            for x in 0..<grid.cols {
                let k = (firstLine + y) * grid.cols + x
                if k >= typed { return }
                grid.cells[y * grid.cols + x] = hash(Double(k) * 0.618) < 0.5 ? 1 : 2
            }
        }
    }
}

// 19. Coloured pipes that wander around the screen, turning at random
final class Pipes: Pattern {
    let name = "Pipes"
    static let shapes = Array("─│┌┐└┘")
    static let palette = [rgb(1, 0.3, 0.3), rgb(0.3, 1, 0.4), rgb(0.35, 0.6, 1),
                          rgb(1, 0.85, 0.3), rgb(0.85, 0.4, 1), rgb(0.3, 0.95, 0.95)]
    // Space, then every pipe shape once per colour
    let chars: [Character] = [" "] + Pipes.palette.flatMap { _ in Pipes.shapes }

    private struct Pipe {
        var x: Int, y: Int
        var dir: Int     // 0 right, 1 down, 2 left, 3 up
        var color: Int
    }

    private var pipes: [Pipe] = []
    private var canvas: [UInt16] = []
    private var cols = 0
    private var rows = 0
    private var lastT = -10.0
    private var pending = 0.0
    private var drawn = 0
    private var random = FastRandom(seed: 88172645)

    func color(_ index: Int) -> CGColor {
        Self.palette[max(0, index - 1) / Self.shapes.count]
    }

    func update(_ grid: inout Grid, t: Double) {
        // Start fresh on a new screen size, or when switching back to this pattern
        if grid.cols != cols || grid.rows != rows || t - lastT > 0.5 {
            reset(cols: grid.cols, rows: grid.rows)
            lastT = t
        }
        // Each pipe moves 60 cells per second
        pending += (t - lastT) * 60
        lastT = t
        while pending >= 1 {
            pending -= 1
            for i in pipes.indices { advance(&pipes[i]) }
        }
        // Wipe the screen once it's mostly full
        if drawn > cols * rows * 3 / 5 {
            for i in canvas.indices { canvas[i] = 0 }
            drawn = 0
        }
        grid.cells = canvas
    }

    private func reset(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        canvas = Array(repeating: 0, count: cols * rows)
        drawn = 0
        pending = 0
        pipes = (0..<Self.palette.count).map { c in
            Pipe(x: Int(random.next() % UInt32(cols)), y: Int(random.next() % UInt32(rows)),
                 dir: Int(random.next() % 4), color: c)
        }
    }

    private func advance(_ p: inout Pipe) {
        var newDir = p.dir
        let r = random.next()
        if r % 100 < 12 { newDir = (p.dir + (r & 128 == 0 ? 1 : 3)) % 4 }
        canvas[p.y * cols + p.x] = UInt16(1 + p.color * Self.shapes.count + shape(from: p.dir, to: newDir))
        p.dir = newDir
        p.x = (p.x + [1, 0, -1, 0][newDir] + cols) % cols
        p.y = (p.y + [0, 1, 0, -1][newDir] + rows) % rows
        drawn += 1
    }

    // Which piece joins the side the pipe came in from to the side it leaves by
    private func shape(from old: Int, to new: Int) -> Int {
        if old == new { return old % 2 == 0 ? 0 : 1 }   // ─ or │
        let inSide = (old + 2) % 4
        let hasRight = inSide == 0 || new == 0
        let hasDown = inSide == 1 || new == 1
        if hasDown { return hasRight ? 2 : 3 }          // ┌ or ┐
        return hasRight ? 4 : 5                          // └ or ┘
    }
}

// 20. A giant clock like tty-clock, with a drop shadow and today's date underneath
final class BigClock: Pattern {
    let name = "Clock"
    let chars: [Character] = Array(" .#ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private let shadow = rgb(0.08, 0.3, 0.4)
    private let block = rgb(0.35, 0.9, 1)
    private let text = rgb(0.6, 0.8, 0.9)
    private var index: [Character: UInt16] = [:]
    private let formatter = DateFormatter()

    // 5x7 pixel digits
    static let digits: [Character: [String]] = [
        "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
        "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
        "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
        "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
        "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
        "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
        "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
        "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
        "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
        ":": ["     ", "  #  ", "  #  ", "     ", "  #  ", "  #  ", "     "],
    ]

    init() {
        for (i, c) in chars.enumerated() { index[c] = UInt16(i) }
        formatter.dateFormat = "EEEE d MMMM yyyy"
    }

    func color(_ index: Int) -> CGColor { index == 1 ? shadow : index == 2 ? block : text }

    func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let now = Date()
        let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        let blink = (parts.nanosecond ?? 0) < 500_000_000
        let glyphs = Array(two(parts.hour) + ":" + two(parts.minute) + ":" + two(parts.second))

        // Make each pixel as big as fits; cells are about twice as tall as wide, so pixels are 2 wide per row
        let pixelW = glyphs.count * 6 - 1
        let sy = max(1, min(grid.cols * 8 / 10 / pixelW / 2, grid.rows * 6 / 10 / 7))
        let sx = sy * 2
        let left = (grid.cols - pixelW * sx) / 2
        let top = (grid.rows - 7 * sy) / 2 - 2

        // Draw the shadow first (offset down and right), then the digits on top
        for (offset, value) in [(1, UInt16(1)), (0, UInt16(2))] {
            for (gi, ch) in glyphs.enumerated() {
                if ch == ":" && !blink { continue }
                guard let bitmap = Self.digits[ch] else { continue }
                for (py, line) in bitmap.enumerated() {
                    for (px, c) in line.enumerated() where c == "#" {
                        let x0 = left + (gi * 6 + px) * sx + offset
                        let y0 = top + py * sy + offset
                        for yy in 0..<sy {
                            for xx in 0..<sx { grid.set(x0 + xx, y0 + yy, value) }
                        }
                    }
                }
            }
        }

        // Today's date, centred under the clock
        let date = Array(formatter.string(from: now).uppercased())
        let dateX = (grid.cols - date.count) / 2
        let dateY = top + 7 * sy + 2
        for (i, c) in date.enumerated() { grid.set(dateX + i, dateY, index[c] ?? 0) }
    }

    private func two(_ n: Int?) -> String {
        let n = n ?? 0
        return n < 10 ? "0\(n)" : "\(n)"
    }
}
