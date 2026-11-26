import Foundation
struct LyricWord: Hashable, Sendable {
    let start: Double
    let end: Double
    let text: String
}
struct LyricLine: Identifiable, Hashable, Sendable {
    var id: Double { time }
    let time: Double
    let text: String
    var translation: String = ""
    var words: [LyricWord] = []
}
enum Lyrics {
    static let stamps = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    static let offset = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
    static let wordMarks = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>"#)
    static let yrcLine = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
    static let yrcWord = try! NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)([^()]*)"#)
    static func seconds(_ ns: NSString, _ match: NSTextCheckingResult) -> Double {
        let fraction = match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
        return (Double(ns.substring(with: match.range(at: 1))) ?? 0) * 60
             + (Double(ns.substring(with: match.range(at: 2))) ?? 0)
             + (Double("0." + fraction) ?? 0)
    }
    static func parse(_ raw: String, translation: String = "") -> [LyricLine] {
        let ns = raw as NSString
        let adjustment = offset.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length))
            .map { (Double(ns.substring(with: $0.range(at: 1))) ?? 0) / 1000 } ?? 0
        var output: [Double: LyricLine] = [:]
        for row in raw.components(separatedBy: .newlines) {
            let source = row as NSString
            let range = NSRange(location: 0, length: source.length)
            if let y = yrcLine.firstMatch(in: row, range: range) {
                let time = max(0, (Double(source.substring(with: y.range(at: 1))) ?? 0) / 1000 + adjustment)
                let text = source.substring(with: y.range(at: 3))
                let words = yrcWord.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map { m -> LyricWord in
                    let s = text as NSString
                    let start = (Double(s.substring(with: m.range(at: 1))) ?? 0) / 1000 + adjustment
                    let duration = (Double(s.substring(with: m.range(at: 2))) ?? 0) / 1000
                    return LyricWord(start: start, end: start + duration, text: s.substring(with: m.range(at: 3)))
                }
                if !words.isEmpty { output[time] = LyricLine(time: time, text: words.map(\.text).joined(), words: words) }
                continue
            }
            let matches = stamps.matches(in: row, range: range)
            guard let last = matches.last else { continue }
            let content = source.substring(from: NSMaxRange(last.range))
            let body = content as NSString
            let enhanced = wordMarks.matches(in: content, range: NSRange(location: 0, length: body.length))
            var words: [LyricWord] = []
            for (index, mark) in enhanced.enumerated() {
                let start = seconds(body, mark) + adjustment
                let end = index + 1 < enhanced.count ? seconds(body, enhanced[index + 1]) + adjustment : start + 0.5
                let lower = NSMaxRange(mark.range)
                let upper = index + 1 < enhanced.count ? enhanced[index + 1].range.location : body.length
                if upper >= lower { words.append(.init(start: start, end: end, text: body.substring(with: NSRange(location: lower, length: upper - lower)))) }
            }
            let text = wordMarks.stringByReplacingMatches(in: content, range: NSRange(location: 0, length: body.length), withTemplate: "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for match in matches {
                let time = max(0, seconds(source, match) + adjustment)
                output[time] = LyricLine(time: time, text: text, words: words)
            }
        }
        var lines = output.values.sorted { $0.time < $1.time }
        if !translation.isEmpty {
            let translated = parse(translation)
            for i in lines.indices {
                if let line = translated.first(where: { abs($0.time - lines[i].time) < 0.12 }) {
                    lines[i].translation = line.text
                }
            }
        }
        return lines
    }
    static func complete(_ primary: [LyricLine], base: [LyricLine]) -> [LyricLine] {
        if primary.isEmpty { return base }
        var result = primary
        for line in base where !primary.contains(where: { abs($0.time - line.time) < 0.18 }) { result.append(line) }
        return result.sorted { $0.time < $1.time }
    }
    static func active(_ lines: [LyricLine], at time: Double) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}
