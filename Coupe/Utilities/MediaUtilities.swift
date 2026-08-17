import Foundation

enum TimeFormatter {
    static func string(_ seconds: Double) -> String {
        let value = max(0, seconds.isFinite ? Int(seconds) : 0)
        let hours = value / 3600, minutes = (value % 3600) / 60, remainder = value % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
                         : String(format: "%d:%02d", minutes, remainder)
    }
}

enum SelectionState: Equatable {
    case idle, pressing(startTime: Double), locked(startTime: Double), finalizing, failed(String)
    var startTime: Double? {
        switch self { case .pressing(let time), .locked(let time): time; default: nil }
    }
}

struct SelectionMachine {
    static let minimumDuration = 0.25
    private(set) var state: SelectionState = .idle

    mutating func begin(at time: Double, duration: Double, ready: Bool) -> Bool {
        guard ready, state == .idle else { return false }
        state = .pressing(startTime: Self.clamp(time, duration: duration)); return true
    }
    mutating func drag(horizontal: Double, vertical: Double, threshold: Double) -> Bool {
        guard case .pressing(let start) = state, horizontal >= threshold,
              abs(vertical) < max(80, abs(horizontal)) else { return false }
        state = .locked(startTime: start); return true
    }
    mutating func release(at time: Double, duration: Double) -> ClosedRange<Double>? {
        guard case .pressing(let start) = state else { return nil }
        return finish(start: start, end: time, duration: duration)
    }
    mutating func stop(at time: Double, duration: Double) -> ClosedRange<Double>? {
        guard case .locked(let start) = state else { return nil }
        return finish(start: start, end: time, duration: duration)
    }
    mutating func cancel() { state = .idle }
    mutating func complete() { state = .idle }
    private mutating func finish(start: Double, end: Double, duration: Double) -> ClosedRange<Double>? {
        let lower = Self.clamp(start, duration: duration), upper = max(lower, Self.clamp(end, duration: duration))
        guard upper - lower >= Self.minimumDuration else { state = .failed("Selection is too short"); return nil }
        state = .finalizing; return lower...upper
    }
    static func clamp(_ value: Double, duration: Double) -> Double { min(max(0, value), max(0, duration)) }
}
