import Foundation

/// Prepared presentation coordinates. Reused while scrubbing; original samples
/// remain selectable even when the rendered series is reduced.
public struct MetricChartProjection: Sendable {
    public struct Point: Identifiable, Sendable {
        public let id: Date
        public let x: Double
        public let value: Double
        public let segment: Int
        public var isolated = false
    }
    public let rendered: [Point]
    private let ordered: [Point]

    public init(metric: WorkoutMetric, coordinate: (Date) -> Double?) {
        let shown = Set(metric.chartPoints.map(\.timestamp))
        var segment = 0
        var previous: Date?
        var previousX: Double?
        var all: [Point] = []
        for sample in metric.points {
            if let previous, sample.timestamp.timeIntervalSince(previous) > 120 { segment += 1 }
            previous = sample.timestamp
            guard let x = coordinate(sample.timestamp), x.isFinite else { segment += 1; continue }
            if let previousX, x < previousX { segment += 1 }
            previousX = x
            all.append(Point(id: sample.timestamp, x: x, value: sample.value, segment: segment))
        }
        var visible = all.filter { shown.contains($0.id) }
        for index in visible.indices {
            visible[index].isolated = (index == 0 || visible[index - 1].segment != visible[index].segment)
                && (index == visible.count - 1 || visible[index + 1].segment != visible[index].segment)
        }
        rendered = visible
        ordered = all.sorted { $0.x == $1.x ? $0.id < $1.id : $0.x < $1.x }
    }

    public func nearest(to selection: Double) -> Point? {
        guard selection.isFinite, !ordered.isEmpty else { return nil }
        var low = 0
        var high = ordered.count
        while low < high {
            let middle = (low + high) / 2
            if ordered[middle].x < selection { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return ordered[0] }
        if low < ordered.count, abs(ordered[low].x - selection) < abs(ordered[low - 1].x - selection) { return ordered[low] }
        // Keep the earliest source sample when several points share this coordinate.
        let x = ordered[low - 1].x
        high = low
        low = 0
        while low < high {
            let middle = (low + high) / 2
            if ordered[middle].x < x { low = middle + 1 } else { high = middle }
        }
        return ordered[low]
    }
}
