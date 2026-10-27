import Foundation
import CoreGraphics
import AVFoundation

// MARK: - Writing coloured text, like a terminal

// The terminal colours the developer patterns can use
enum Ink: Int, CaseIterable {
    case white, gray, red, green, yellow, blue, magenta, cyan, orange, bright
}

let inkColors: [CGColor] = [
    rgb(0.82, 0.84, 0.86), rgb(0.42, 0.45, 0.5), rgb(1, 0.37, 0.37), rgb(0.35, 0.86, 0.45), rgb(1, 0.83, 0.3),
    rgb(0.38, 0.6, 1), rgb(0.85, 0.45, 1), rgb(0.3, 0.85, 0.9), rgb(1, 0.6, 0.25), rgb(1, 1, 1),
]

// A piece of text and its colour
typealias Span = (String, Ink)

// Base for the developer patterns: every printable character in every Ink colour,
// plus helpers to write text and endless scrolling output into the grid
class TextPattern: Pattern {
    let name: String
    static let charset: [Character] = (33...126).map { Character(UnicodeScalar(UInt8($0))) } + Array("█░▒▓│─├└┬┤┼✓✗●")
    static let lookup = Dictionary(uniqueKeysWithValues: charset.enumerated().map { ($1, $0) })
    let chars: [Character] = [" "] + Ink.allCases.flatMap { _ in TextPattern.charset }

    init(name: String) {
        self.name = name
    }

    func color(_ index: Int) -> CGColor {
        inkColors[max(0, index - 1) / Self.charset.count]
    }

    func update(_ grid: inout Grid, t: Double) {}

    // Declared here (not just in the protocol extension) so subclasses can override them
    func activate() {}
    func deactivate() {}

    // The cell value for one character in one colour
    func code(_ ch: Character, _ ink: Ink) -> UInt16 {
        guard let i = Self.lookup[ch] else { return 0 }
        return UInt16(1 + ink.rawValue * Self.charset.count + i)
    }

    // Writes text starting at column x, row y (at most `limit` characters). Returns the column after it
    @discardableResult
    func write(_ text: String, _ x: Int, _ y: Int, _ ink: Ink, _ grid: inout Grid, limit: Int = .max) -> Int {
        var col = x
        for ch in text.prefix(limit) {
            if ch != " " { grid.set(col, y, code(ch, ink)) }
            col += 1
        }
        return col
    }

    @discardableResult
    func write(_ spans: [Span], _ x: Int, _ y: Int, _ grid: inout Grid, limit: Int = .max) -> Int {
        var col = x
        var left = limit
        for (text, ink) in spans where left > 0 {
            let start = col
            col = write(text, col, y, ink, &grid, limit: left)
            left -= col - start
        }
        return col
    }

    // An endless stream of lines scrolling up between rows `top` and `bottom`. line(n) describes line n.
    // The newest line is still being typed; its first `keep` characters show straight away
    func scroll(_ grid: inout Grid, t: Double, linesPerSecond: Double, top: Int = 0, bottom: Int? = nil,
                x: Int = 0, keep: Int = 0, cursor: Bool = false, line: (Int) -> [Span]) {
        let rows = (bottom ?? grid.rows) - top
        guard rows > 0 else { return }
        let progress = t * linesPerSecond
        let newest = Int(progress)
        for r in 0..<rows {
            let n = newest - (rows - 1 - r)
            guard n >= 0 else { continue }
            let spans = line(n)
            if n == newest {
                let total = spans.reduce(0) { $0 + $1.0.count }
                let shown = keep + Int(Double(max(0, total - keep)) * (progress - floor(progress)))
                let end = write(spans, x, top + r, &grid, limit: shown)
                if cursor { write("█", end, top + r, .bright, &grid) }
            } else {
                write(spans, x, top + r, &grid)
            }
        }
    }
}

// Small helpers shared by the patterns below
func pick<T>(_ list: [T], _ seed: Double) -> T {
    list[min(list.count - 1, Int(hash(seed) * Double(list.count)))]
}

func hexString(_ seed: Int, _ digits: Int) -> String {
    let s = String(Int(hash(Double(seed) * 0.917) * pow(16, Double(digits))), radix: 16)
    return String(repeating: "0", count: max(0, digits - s.count)) + s
}

func zeroPad(_ n: Int, _ width: Int) -> String {
    let s = String(n)
    return String(repeating: "0", count: max(0, width - s.count)) + s
}

func padLeft(_ s: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - s.count)) + s
}

func padRight(_ s: String, _ width: Int) -> String {
    s + String(repeating: " ", count: max(0, width - s.count))
}

// Some made-up Swift used by the code editor and the diff
let sampleCode = [
    "import Foundation",
    "",
    "// Keeps recent responses so we don't hit the network twice",
    "final class ResponseCache {",
    "    private var entries: [URL: Entry] = [:]",
    "    private let maxAge: TimeInterval = 300",
    "",
    "    struct Entry {",
    "        let data: Data",
    "        let savedAt: Date",
    "    }",
    "",
    "    func load(_ url: URL) async throws -> Data {",
    "        if let hit = entries[url], !isStale(hit) {",
    "            return hit.data",
    "        }",
    "        let (data, response) = try await URLSession.shared.data(from: url)",
    "        guard let http = response as? HTTPURLResponse,",
    "              http.statusCode == 200 else {",
    "            throw CacheError.badStatus",
    "        }",
    "        entries[url] = Entry(data: data, savedAt: Date())",
    "        return data",
    "    }",
    "",
    "    private func isStale(_ entry: Entry) -> Bool {",
    "        Date().timeIntervalSince(entry.savedAt) > maxAge",
    "    }",
    "",
    "    func purge() {",
    "        for (url, entry) in entries where isStale(entry) {",
    "            entries[url] = nil",
    "        }",
    "        print(\"purged, \\(entries.count) left\")",
    "    }",
    "}",
    "",
    "enum CacheError: Error {",
    "    case badStatus",
    "    case timedOut(after: Int)",
    "}",
    "",
]

let swiftKeywords: Set<String> = [
    "func", "let", "var", "if", "else", "guard", "return", "for", "in", "while", "struct", "class", "final",
    "private", "static", "import", "switch", "case", "default", "async", "await", "try", "throw", "throws",
    "self", "nil", "true", "false", "extension", "protocol", "enum", "init", "where", "as",
]

// Colours a line of Swift: keywords, types, strings, numbers and comments
func highlightSwift(_ line: String) -> [Span] {
    var out: [Span] = []
    let chars = Array(line)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
            out.append((String(chars[i...]), .gray))
            break
        }
        var j = i + 1
        if c == "\"" {
            while j < chars.count && chars[j] != "\"" { j += 1 }
            j = min(j + 1, chars.count)
            out.append((String(chars[i..<j]), .green))
        } else if c.isLetter || c == "_" {
            while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
            let word = String(chars[i..<j])
            out.append((word, swiftKeywords.contains(word) ? .magenta : word.first!.isUppercase ? .cyan : .white))
        } else if c.isNumber {
            while j < chars.count && (chars[j].isNumber || chars[j] == ".") { j += 1 }
            out.append((String(chars[i..<j]), .orange))
        } else {
            out.append((String(c), .white))
        }
        i = j
    }
    return out
}

func developerPatterns() -> [Pattern] {
    [CodeEditor(), GitLog(), ServerLogs(), Htop(), SortVisualizer(),
     GitDiff(), KubePods(), Disassembly(), PackageInstall(), DirectoryTree(), WebcamPattern()]
}

// MARK: - The developer patterns

// 21. Code being typed into vim, with line numbers, syntax colours and a status line
final class CodeEditor: TextPattern {
    private let lines = sampleCode.map(highlightSwift)

    init() { super.init(name: "Code editor") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let rate = 2.5
        scroll(&grid, t: t, linesPerSecond: rate, bottom: grid.rows - 2, keep: 6, cursor: true) { n in
            [(padLeft(String(n + 1), 4) + "  ", .gray)] + lines[n % lines.count]
        }
        write(String(repeating: "─", count: grid.cols), 0, grid.rows - 2, .gray, &grid)
        write("-- INSERT --", 0, grid.rows - 1, .bright, &grid)
        let column = Int((t * rate - floor(t * rate)) * 40) + 1
        let info = "ResponseCache.swift [+]   \(Int(t * rate) + 1),\(column)   swift   utf-8"
        write(info, grid.cols - info.count - 2, grid.rows - 1, .gray, &grid)
    }
}

// 22. `git log --graph` with a feature branch splitting off and merging back
final class GitLog: TextPattern {
    private let graph = ["* ", "* ", "|\\  ", "| * ", "| * ", "* | ", "|/  ", "* "]
    private let verbs = ["Fix", "Add", "Refactor", "Update", "Remove", "Bump", "Improve", "Revert", "Speed up", "Clean up"]
    private let things = ["login flow", "race in cache", "dark mode", "API client", "flaky test", "build script",
                          "README", "dependencies", "memory leak", "parser edge case", "retry logic", "CI config",
                          "error messages", "onboarding screen"]
    private let authors = ["alex", "sam", "jordan", "kai", "riley", "morgan", "dev"]

    init() { super.init(name: "Git log") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        scroll(&grid, t: t, linesPerSecond: 4, keep: 4) { n in line(n) }
    }

    private func line(_ n: Int) -> [Span] {
        // The graph: the main branch in red, the feature branch in green
        let g = graph[n % graph.count]
        var spans: [Span] = g.enumerated().map { i, ch in (String(ch), i == 0 ? .red : .green) }
        guard g.contains("*") else { return spans }

        let seed = Double(n)
        spans.append((hexString(n, 7), .yellow))
        spans.append((" - ", .white))
        if n % 41 == 0 {
            spans += [("(", .yellow), ("HEAD -> ", .cyan), ("main", .green), (", ", .yellow),
                      ("origin/main", .red), (") ", .yellow)]
        } else if n % 17 == 3 {
            let branch = "feature/" + pick(things, seed * 0.3).replacingOccurrences(of: " ", with: "-")
            spans += [("(", .yellow), (branch, .green), (") ", .yellow)]
        }
        spans.append((pick(verbs, seed * 1.1) + " " + pick(things, seed * 0.7), .white))
        spans.append((" (\(1 + n * 7 % 58) minutes ago)", .green))
        spans.append((" <\(pick(authors, seed * 0.13))>", .blue))
        return spans
    }
}

// 23. `tail -f` on a busy web server: requests, slow queries, the odd error
final class ServerLogs: TextPattern {
    private let paths = ["/api/v1/users", "/api/v1/orders", "/api/v1/cart", "/health", "/api/v1/search?q=shoes",
                         "/static/app.js", "/api/v1/login", "/api/v1/payments"]
    private let methods = ["GET", "GET", "GET", "POST", "PUT", "DELETE"]
    private let errors = ["upstream timed out (504) while reading /api/v1/checkout",
                          "db: connection reset by peer (retry 2/5)",
                          "unhandled exception in OrderService.place: index out of range",
                          "rate limit exceeded for client 10.0.4.17",
                          "TLS handshake failed: certificate expired"]

    init() { super.init(name: "Server logs") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        scroll(&grid, t: t, linesPerSecond: 12, keep: 13) { n in line(n) }
    }

    private func line(_ n: Int) -> [Span] {
        let s = 9 * 3600 + Double(n) * 0.083
        let time = "\(zeroPad(Int(s) / 3600 % 24, 2)):\(zeroPad(Int(s) / 60 % 60, 2)):\(zeroPad(Int(s) % 60, 2))"
            + ".\(zeroPad(Int(s * 1000) % 1000, 3)) "
        let seed = Double(n)
        let h = hash(seed * 0.71)
        let worker: Span = (" [w\(n % 8)] ", .cyan)

        if h < 0.04 {
            return [(time, .gray), ("ERROR", .red), worker, (pick(errors, seed * 0.3), .red)]
        }
        if h < 0.13 {
            let ms = 200 + Int(hash(seed + 3) * 900)
            return [(time, .gray), ("WARN ", .yellow), worker,
                    ("slow query \(ms)ms: SELECT * FROM orders WHERE user_id = \(Int(hash(seed + 4) * 99999))", .white)]
        }
        if h < 0.3 {
            return [(time, .gray), ("DEBUG", .gray), worker, ("cache hit key=session:\(hexString(n, 4)) ttl=3600", .gray)]
        }
        let status = h > 0.96 ? 404 : h > 0.94 ? 500 : 200
        let statusInk: Ink = status == 200 ? .green : status == 404 ? .yellow : .red
        let ms = 2 + Int(pow(hash(seed + 5), 3) * 400)
        return [(time, .gray), ("INFO ", .green), worker, (pick(methods, seed * 0.9) + " ", .blue),
                (pick(paths, seed * 1.3) + " ", .white), ("\(status)", statusInk), (" \(ms)ms", .gray)]
    }
}

// 24. A system monitor: CPU and memory meters, then the busiest processes
final class Htop: TextPattern {
    private let procs: [(String, String, Double)] = [
        ("dev", "node server.js", 0.9), ("dev", "xcodebuild -scheme xd-loop", 1.0),
        ("dev", "swift-frontend -c main.swift", 0.8), ("root", "kernel_task", 0.5),
        ("_windowserver", "WindowServer", 0.45), ("dev", "Docker Desktop", 0.6),
        ("dev", "postgres: checkpointer", 0.3), ("dev", "redis-server *:6379", 0.25),
        ("dev", "python3 train.py", 0.95), ("dev", "cargo build --release", 0.85),
        ("dev", "xd-loop", 0.35), ("dev", "Code Helper (Renderer)", 0.4),
        ("root", "mds_stores", 0.2), ("dev", "Slack Helper", 0.15), ("dev", "git fetch --all", 0.3),
        ("root", "launchd", 0.05), ("dev", "zsh", 0.02), ("dev", "ssh prod-db-1", 0.05),
        ("root", "syslogd", 0.03), ("dev", "Safari Web Content", 0.25),
    ]

    init() { super.init(name: "htop") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let half = grid.cols / 2
        let barW = max(12, half - 8)
        let sample = floor(t * 2) / 2   // meters refresh twice a second

        for core in 0..<8 {
            let c = Double(core)
            let load = max(0.02, min(1, 0.5 + 0.3 * sin(sample * 0.9 + c * 1.7) + 0.2 * sin(sample * 2.3 + c)))
            meter(padLeft("\(core + 1)", 3), load, String(format: "%.1f%%", load * 100),
                  x: core < 4 ? 0 : half, y: core % 4, width: barW, &grid)
        }
        let mem = 0.38 + 0.04 * sin(t * 0.3)
        meter("Mem", mem, String(format: "%.1fG/32.0G", mem * 32), x: 0, y: 4, width: barW, &grid)
        meter("Swp", 0.06, "0.2G/4.0G", x: 0, y: 5, width: barW, &grid)

        let up = Int(t) + 273_164
        write("Tasks: 412, 1873 thr; \(2 + Int(sample) % 4) running", half + 2, 4, .white, &grid)
        write(String(format: "Load average: %.2f %.2f %.2f", 2 + sin(sample * 0.2), 1.9 + sin(sample * 0.05) * 0.3, 1.75),
              half + 2, 5, .white, &grid)
        write("Uptime: \(up / 86400) days, \(zeroPad(up / 3600 % 24, 2)):\(zeroPad(up / 60 % 60, 2)):\(zeroPad(up % 60, 2))",
              half + 2, 6, .white, &grid)

        // Busiest processes first; their numbers refresh every 1.5 seconds
        let tick = floor(t / 1.5)
        let busiest = procs.enumerated()
            .map { i, p in (i, p, p.2 * (0.35 + 0.65 * hash(tick * 13 + Double(i)))) }
            .sorted { $0.2 > $1.2 }
        write("    PID USER        PRI  NI   VIRT    RES S  CPU%  MEM%     TIME+  Command", 0, 8, .green, &grid)
        for (row, (i, p, cpu)) in busiest.enumerated() {
            let y = 9 + row
            if y >= grid.rows - 1 { break }
            let selected = row == 0
            let ink: Ink = selected ? .cyan : .white
            let secs = t * cpu + Double(i) * 97
            let time = "\(Int(secs) / 60):\(zeroPad(Int(secs) % 60, 2)).\(zeroPad(Int(secs * 100) % 100, 2))"
            var x = write(padLeft("\(300 + i * 487 % 9000)", 7) + " ", 0, y, selected ? .cyan : .gray, &grid)
            x = write(padRight(p.0, 11) + " ", x, y, ink, &grid)
            x = write(" 20   0  " + padLeft("\(Int(4 + hash(Double(i)) * 400))G", 5) + "  "
                      + padLeft("\(Int(20 + hash(Double(i) + 1) * 900))M", 5) + " ", x, y, ink, &grid)
            x = write(cpu > 0.5 ? "R " : "S ", x, y, cpu > 0.5 ? .green : ink, &grid)
            x = write(padLeft(String(format: "%.1f", cpu * 100), 5) + " ", x, y, cpu > 0.8 ? .red : ink, &grid)
            x = write(padLeft(String(format: "%.1f", 0.2 + hash(Double(i) * 3.3) * 6), 5) + " ", x, y, ink, &grid)
            x = write(padLeft(time, 9) + "  ", x, y, ink, &grid)
            write(p.1, x, y, selected ? .cyan : .bright, &grid)
        }

        // Function key bar along the bottom
        var x = 0
        for (key, label) in [("F1", "Help"), ("F2", "Setup"), ("F3", "Search"), ("F4", "Filter"), ("F5", "Tree"),
                             ("F6", "SortBy"), ("F7", "Nice -"), ("F8", "Nice +"), ("F9", "Kill"), ("F10", "Quit")] {
            x = write(key, x, grid.rows - 1, .bright, &grid)
            x = write(padRight(label, 7), x, grid.rows - 1, .cyan, &grid)
        }
    }

    // A meter like "  1[||||||||        45.2%]": mostly green, the top quarter red
    private func meter(_ label: String, _ value: Double, _ text: String, x: Int, y: Int, width: Int, _ grid: inout Grid) {
        var col = write(label, x, y, .cyan, &grid)
        col = write("[", col, y, .bright, &grid)
        let filled = Int(value * Double(width - text.count))
        let green = filled * 3 / 4
        write(String(repeating: "|", count: green), col, y, .green, &grid)
        write(String(repeating: "|", count: filled - green), col + green, y, .red, &grid)
        write(text, col + width - text.count, y, .gray, &grid)
        write("]", col + width, y, .bright, &grid)
    }
}

// 25. Sorting algorithms, swap by swap. Each run is recorded first, then played back over ~8 seconds
final class SortVisualizer: TextPattern {
    private let names = ["quicksort", "insertion sort", "selection sort", "heapsort"]
    private var values: [Int] = []
    private var ops: [(Int, Int)] = []
    private var done = 0
    private var lastSwap: (Int, Int)?
    private var algorithm = -1
    private var finishedAt: Double?
    private var lastT = -10.0
    private var pending = 0.0
    private var cols = 0
    private var rows = 0
    private var random = FastRandom(seed: 4242)

    init() { super.init(name: "Sorting") }

    override func update(_ grid: inout Grid, t: Double) {
        // Start a fresh sort on a new screen size, or when switching back to this pattern
        if grid.cols != cols || grid.rows != rows || t - lastT > 0.5 {
            cols = grid.cols
            rows = grid.rows
            start()
            lastT = t
        }

        pending += (t - lastT) * max(1, Double(ops.count) / 8)
        lastT = t
        while pending >= 1 && done < ops.count {
            pending -= 1
            let (i, j) = ops[done]
            values.swapAt(i, j)
            lastSwap = (i, j)
            done += 1
        }
        if done == ops.count {
            if finishedAt == nil { finishedAt = t }
            if let f = finishedAt, t - f > 2 { start() }
        }

        grid.clear()
        let title = names[algorithm % names.count]
        write(title, 1, 0, .bright, &grid)
        write("   \(values.count) items · \(done)/\(ops.count) swaps", 1 + title.count, 0, .gray, &grid)
        let floorRow = grid.rows - 1
        for k in values.indices {
            let swapped = lastSwap.map { $0.0 == k || $0.1 == k } ?? false
            let bar = code("█", finishedAt != nil ? .green : swapped ? .red : .cyan)
            for h in 0..<values[k] { grid.set(1 + k * 2, floorRow - h, bar) }
        }
    }

    // Shuffle new bars and record every swap the next algorithm makes
    private func start() {
        algorithm += 1
        let count = max(2, (cols - 2) / 2)
        let height = max(2, rows - 3)
        values = (0..<count).map { 1 + $0 * (height - 1) / (count - 1) }
        for i in stride(from: count - 1, to: 0, by: -1) {
            values.swapAt(i, Int(random.next() % UInt32(i + 1)))
        }
        ops = record(values, algorithm % names.count)
        done = 0
        pending = 0
        lastSwap = nil
        finishedAt = nil
    }

    private func record(_ input: [Int], _ which: Int) -> [(Int, Int)] {
        var a = input
        var ops: [(Int, Int)] = []
        func swap(_ i: Int, _ j: Int) {
            guard i != j else { return }
            a.swapAt(i, j)
            ops.append((i, j))
        }
        switch which {
        case 0:
            func quicksort(_ lo: Int, _ hi: Int) {
                guard lo < hi else { return }
                let pivot = a[hi]
                var i = lo
                for j in lo..<hi where a[j] < pivot {
                    swap(i, j)
                    i += 1
                }
                swap(i, hi)
                quicksort(lo, i - 1)
                quicksort(i + 1, hi)
            }
            quicksort(0, a.count - 1)
        case 1:
            for i in 1..<a.count {
                var j = i
                while j > 0 && a[j - 1] > a[j] {
                    swap(j - 1, j)
                    j -= 1
                }
            }
        case 2:
            for i in 0..<a.count {
                var smallest = i
                for j in i..<a.count where a[j] < a[smallest] { smallest = j }
                swap(i, smallest)
            }
        default:
            func siftDown(_ start: Int, _ end: Int) {
                var root = start
                while 2 * root + 1 <= end {
                    var child = 2 * root + 1
                    if child + 1 <= end && a[child] < a[child + 1] { child += 1 }
                    guard a[root] < a[child] else { return }
                    swap(root, child)
                    root = child
                }
            }
            for s in stride(from: (a.count - 2) / 2, through: 0, by: -1) { siftDown(s, a.count - 1) }
            for end in stride(from: a.count - 1, to: 0, by: -1) {
                swap(0, end)
                siftDown(0, end - 1)
            }
        }
        return ops
    }
}

// 26. `git diff`: file headers, hunks, and red/green changed lines
final class GitDiff: TextPattern {
    private let files = ["Cache/ResponseCache.swift", "UI/ContentView.swift", "Net/APIClient.swift",
                         "Models/Order.swift", "App/AppDelegate.swift"]

    init() { super.init(name: "Git diff") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        scroll(&grid, t: t, linesPerSecond: 7, keep: 1) { n in line(n) }
    }

    private func line(_ n: Int) -> [Span] {
        let block = n / 18
        let file = pick(files, Double(block) * 2.1)
        switch n % 18 {
        case 0: return [("diff --git a/\(file) b/\(file)", .bright)]
        case 1: return [("index \(hexString(block, 7))..\(hexString(block + 999, 7)) 100644", .gray)]
        case 2: return [("--- a/\(file)", .red)]
        case 3: return [("+++ b/\(file)", .green)]
        case 4:
            let start = 10 + Int(hash(Double(block)) * 200)
            return [("@@ -\(start),12 +\(start),14 @@", .cyan), (" func load(_ url: URL) async throws -> Data {", .gray)]
        case 17: return []
        default:
            let code = sampleCode[(block * 7 + n % 18) % sampleCode.count]
            let h = hash(Double(n) * 0.53)
            if h < 0.2 { return [("-" + code, .red)] }
            if h < 0.42 { return [("+" + code, .green)] }
            return [(" " + code, .white)]
        }
    }
}

// 27. `kubectl get pods -w`: pods starting, running, crash-looping and being replaced
final class KubePods: TextPattern {
    private let services = ["api", "web", "worker", "auth", "payments", "search", "redis", "postgres",
                            "ingress-nginx", "metrics", "scheduler", "notifier"]
    private let namespaces = ["default", "prod", "staging", "kube-system", "monitoring"]

    init() { super.init(name: "Kubernetes pods") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        write("$ ", 0, 0, .green, &grid)
        write("kubectl get pods -A -w", 2, 0, .white, &grid)
        let columns = [0, 14, 50, 58, 78, 89]
        for (i, h) in ["NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "AGE"].enumerated() {
            write(h, columns[i], 2, .bright, &grid)
        }

        for row in 0..<max(0, grid.rows - 4) {
            // Each pod lives for its own length of time, then gets replaced with a new name
            let r = Double(row)
            let period = 25 + hash(r * 3.1) * 35
            let clock = t + hash(r * 7.7) * period
            let cycle = Int(clock / period)
            let age = clock.truncatingRemainder(dividingBy: period)
            let f = age / period
            let crashy = hash(r * 1.9) < 0.18

            var status = "Running", ink = Ink.green, restarts = Int(hash(r) * 1.5)
            if f < 0.06 {
                status = "Pending"; ink = .yellow
            } else if f < 0.13 {
                status = "ContainerCreating"; ink = .yellow
            } else if crashy {
                let k = Int((f - 0.13) * 12)
                restarts = (k + 2) / 3
                if k % 3 == 1 { status = "Error"; ink = .red }
                if k % 3 == 2 { status = "CrashLoopBackOff"; ink = .red }
            } else if f > 0.93 {
                status = "Terminating"; ink = .magenta
            }

            let y = row + 3
            let name = pick(services, r * 0.37) + "-" + hexString(row * 131 + cycle, 9) + "-" + hexString(row * 71 + cycle * 3, 5)
            let secs = Int(age)
            write(pick(namespaces, r * 0.61), columns[0], y, .gray, &grid)
            write(name, columns[1], y, .white, &grid)
            write(status == "Running" ? "1/1" : "0/1", columns[2], y, status == "Running" ? .green : .gray, &grid)
            write(status, columns[3], y, ink, &grid)
            write("\(restarts)", columns[4], y, restarts > 0 ? .orange : .white, &grid)
            write(secs < 60 ? "\(secs)s" : "\(secs / 60)m\(secs % 60)s", columns[5], y, .gray, &grid)
        }
    }
}

// 28. Stepping through arm64 assembly in a debugger, with the current instruction marked
final class Disassembly: TextPattern {
    private let functions = ["xd-loop`AsciiView.draw(_:)", "xd-loop`DoomFire.step()", "xd-loop`Grid.set(_:_:_:)",
                             "libswiftCore.dylib`swift_retain", "xd-loop`AppDelegate.handleKey(_:)",
                             "xd-loop`FieldPattern.update(_:t:)"]
    private let ops = ["stp", "ldp", "mov", "add", "sub", "ldr", "str", "bl", "cmp", "b.ne", "b.eq", "cbz", "adrp", "fmul", "fadd"]
    private let symbols = ["swift_retain", "swift_release", "objc_msgSend", "CTFontDrawGlyphs", "memcpy", "swift_beginAccess"]

    init() { super.init(name: "Disassembly") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let rate = 6.0
        let current = Int(t * rate) - 3
        scroll(&grid, t: t, linesPerSecond: rate, keep: 30) { n in line(n, current: current) }
    }

    private func line(_ n: Int, current: Int) -> [Span] {
        let k = n % 26
        if k == 0 { return [(pick(functions, Double(n / 26) * 1.3) + ":", .bright)] }
        let here = n == current
        let op = k == 1 ? "stp" : k == 2 ? "mov" : k == 25 ? "ret" : pick(ops, Double(n) * 0.77)
        var spans: [Span] = [(here ? "->  " : "    ", .green),
                             ("0x" + String(0x100003f00 + n * 4, radix: 16), here ? .green : .cyan),
                             (" " + padRight("<+\((k - 1) * 4)>:", 8) + " ", .gray),
                             (padRight(op, 7), .yellow)]
        spans += operandSpans(operands(op, n))
        return spans
    }

    private func operands(_ op: String, _ n: Int) -> String {
        let r1 = n * 7 % 20, r2 = n * 13 % 29
        let target = "0x" + String(0x100003f00 + (n + 9) * 4, radix: 16)
        switch op {
        case "stp": return "x29, x30, [sp, #-0x10]!"
        case "ldp": return "x29, x30, [sp], #0x10"
        case "mov", "cmp": return "x\(r1), x\(r2)"
        case "add", "sub": return "x\(r1), x\(r1), #0x\(String(n % 15 + 1, radix: 16))"
        case "ldr", "str": return "x\(r1), [x\(r2), #0x\(String(n % 8 * 8, radix: 16))]"
        case "bl": return "\(target) ; symbol stub for: \(pick(symbols, Double(n) * 0.31))"
        case "b.ne", "b.eq": return "\(target) ; <+\(n % 26 * 4 + 36)>"
        case "cbz": return "x\(r1), \(target)"
        case "adrp": return "x\(r1), \(n % 9) ; 0x100008000"
        case "fmul", "fadd": return "d\(n % 8), d\(n % 5), d\(n % 3)"
        default: return ""
        }
    }

    // Registers green, numbers magenta, addresses cyan, comments grey
    private func operandSpans(_ s: String) -> [Span] {
        let parts = s.split(separator: ";", maxSplits: 1).map(String.init)
        var out: [Span] = []
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let isRegister = ["sp", "fp", "lr"].contains(token)
                || (token.count > 1 && "xwd".contains(token.first!) && token.dropFirst().allSatisfy(\.isNumber))
            let ink: Ink = token.hasPrefix("#") ? .magenta : token.hasPrefix("0x") ? .cyan : isRegister ? .green : .white
            out.append((token, ink))
            token = ""
        }
        for ch in parts.first ?? "" {
            if " ,[]!".contains(ch) {
                flush()
                out.append((String(ch), .white))
            } else {
                token.append(ch)
            }
        }
        flush()
        if parts.count > 1 { out.append((";" + parts[1], .gray)) }
        return out
    }
}

// 29. `npm install`: a wall of download bars, each finishing and starting the next package
final class PackageInstall: TextPattern {
    private let packages = ["react", "typescript", "lodash", "express", "webpack", "vite", "eslint", "prettier",
                            "axios", "zod", "jest", "tailwindcss", "next", "esbuild", "rxjs", "dayjs", "chalk",
                            "commander", "uuid", "ws", "sharp", "prisma", "graphql", "redux"]

    init() { super.init(name: "npm install") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        write("$ ", 0, 0, .green, &grid)
        write("npm install", 2, 0, .white, &grid)
        let barW = max(10, min(40, grid.cols - 60))
        let spinner = Array("|/-\\")
        var installed = 0

        for row in 0..<max(0, grid.rows - 4) {
            let r = Double(row)
            let period = 4 + hash(r * 2.3) * 7
            let clock = t + hash(r * 5.1) * period
            let cycle = Int(clock / period)
            let f = clock.truncatingRemainder(dividingBy: period) / period
            installed += cycle
            let seed = r * 0.91 + Double(cycle) * 1.7
            let version = "\(Int(hash(seed) * 20)).\(Int(hash(seed + 1) * 30)).\(Int(hash(seed + 2) * 12))"
            let label = padRight(pick(packages, seed) + "@" + version, 26)
            let y = row + 2

            if f < 0.75 {
                let p = f / 0.75
                let filled = Int(p * Double(barW))
                write(String(spinner[(Int(t * 10) + row) % 4]), 0, y, .cyan, &grid)
                write(label, 2, y, .white, &grid)
                write(String(repeating: "█", count: filled), 29, y, .green, &grid)
                write(String(repeating: "░", count: barW - filled), 29 + filled, y, .gray, &grid)
                write(padLeft("\(Int(p * 100))%", 4), 30 + barW, y, .bright, &grid)
                write(String(format: "%.1f MB/s", 0.5 + hash(seed + 3) * 9), 36 + barW, y, .gray, &grid)
            } else {
                write("✓", 0, y, .green, &grid)
                write(label, 2, y, .gray, &grid)
                write(String(format: "done in %.1fs", period * 0.75), 29, y, .gray, &grid)
            }
        }
        write("added \(installed) packages, audited \(installed * 3) in \(Int(t))s", 0, grid.rows - 1, .gray, &grid)
    }
}

// 30. `tree` listing an endless project: folders in blue, files coloured by type
final class DirectoryTree: TextPattern {
    private let folders = ["src", "components", "utils", "tests", "api", "models", "views", "hooks", "assets",
                           "config", "scripts", "lib", "internal", "fixtures", "docs", "styles"]
    private let files: [Span] = [("index.ts", .blue), ("App.tsx", .blue), ("main.swift", .orange), ("README.md", .white),
                                 ("package.json", .yellow), ("utils.js", .yellow), ("server.go", .cyan), ("lib.rs", .orange),
                                 ("train.py", .cyan), ("logo.png", .magenta), ("icon.svg", .magenta), ("config.yml", .red),
                                 ("Dockerfile", .blue), ("Cargo.lock", .gray), (".gitignore", .gray), ("schema.sql", .yellow),
                                 ("styles.css", .magenta), ("Makefile", .white)]
    // How deep each line is; worked out once and remembered, as a random walk
    private var depths = [0]
    private var random = FastRandom(seed: 777)

    init() { super.init(name: "Directory tree") }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        let rate = 9.0
        scroll(&grid, t: t, linesPerSecond: rate, bottom: grid.rows - 2) { n in line(n) }
        let shown = Int(t * rate)
        write("\(shown * 3 / 10) directories, \(shown - shown * 3 / 10) files", 0, grid.rows - 1, .gray, &grid)
    }

    private func depth(_ n: Int) -> Int {
        while depths.count <= n + 1 {
            let d = depths[depths.count - 1]
            let r = random.next() % 100
            depths.append(r < 35 ? min(d + 1, 7) : r < 70 ? max(d, 1) : max(1, d - 1 - Int(random.next() % 2)))
        }
        return depths[n]
    }

    private func line(_ n: Int) -> [Span] {
        if n == 0 { return [(".", .blue)] }
        let d = depth(n), next = depth(n + 1)
        // A line is a folder if the next one is inside it, and the last in its folder if the next one is shallower
        let branch = String(repeating: "│   ", count: d - 1) + (next < d ? "└── " : "├── ")
        if next > d { return [(branch, .gray), (pick(folders, Double(n) * 0.73) + "/", .blue)] }
        return [(branch, .gray), pick(files, Double(n) * 0.37)]
    }
}

// 31. You, live from the webcam, in green characters. Brighter parts get denser characters.
// The camera is only on while this pattern is on screen
final class WebcamPattern: TextPattern {
    private let shades = Array(" .:-=+*#%@")
    private var isActive = false

    init() { super.init(name: "Webcam") }

    override func activate() {
        isActive = true
        switch CameraFeed.status {
        case .authorized:
            CameraFeed.shared.start()
        case .notDetermined:
            // macOS's permission prompt would be hidden under the cover, so the cover steps back while it's up
            NotificationCenter.default.post(name: .permissionPrompt, object: true)
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                NotificationCenter.default.post(name: .permissionPrompt, object: false)
                if granted && isActive { CameraFeed.shared.start() }
            }
        default:
            break
        }
    }

    override func deactivate() {
        isActive = false
        CameraFeed.shared.stop()
    }

    override func update(_ grid: inout Grid, t: Double) {
        grid.clear()
        guard let frame = CameraFeed.shared.latest else {
            let blocked = CameraFeed.status == .denied || CameraFeed.status == .restricted
            let lines = blocked ? ["Camera access is off.", "Allow xd-loop under Camera in Privacy & Security."]
                                : ["Waiting for the camera..."]
            for (i, line) in lines.enumerated() {
                write(line, (grid.cols - line.count) / 2, grid.rows / 2 + i, .green, &grid)
            }
            return
        }

        // Stretch the contrast so a dim room still uses the whole range of characters
        let lo = Double(frame.min() ?? 0), hi = Double(max(frame.max() ?? 255, (frame.min() ?? 0) + 1))

        // Fill the screen, cropping the picture; a text cell is about twice as tall as it is wide
        let camW = Double(CameraFeed.width), camH = Double(CameraFeed.height)
        let scale = max(Double(grid.cols) / camW, Double(grid.rows) * 2 / camH)
        let offsetX = (camW - Double(grid.cols) / scale) / 2
        let offsetY = (camH - Double(grid.rows) * 2 / scale) / 2
        let codes = shades.enumerated().map { i, ch in code(ch, i >= 8 ? .bright : .green) }

        for row in 0..<grid.rows {
            let sy = min(CameraFeed.height - 1, max(0, Int(offsetY + Double(row) * 2 / scale)))
            for col in 0..<grid.cols {
                let sx = min(CameraFeed.width - 1, max(0, Int(offsetX + Double(col) / scale)))
                let v = (Double(frame[sy * CameraFeed.width + sx]) - lo) / (hi - lo)
                grid.cells[row * grid.cols + col] = codes[min(shades.count - 1, max(0, Int(v * Double(shades.count))))]
            }
        }
    }
}
