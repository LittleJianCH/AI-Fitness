import Foundation
import XCTest
@testable import FitnessCore

final class ChartSamplesTests: XCTestCase {
    func testSmallSeriesIsUnchanged() {
        for count in [0, 1, 2, 600] {
            let metric = makeMetric((0..<count).map(Double.init))
            XCTAssertEqual(metric.chartPoints.map(\.timestamp), metric.points.map(\.timestamp))
            XCTAssertEqual(metric.chartPoints.map(\.value), metric.points.map(\.value))
        }
    }

    func testDenseSeriesRetainsEndpointsPeaksZerosAndOrder() throws {
        var values = Array(repeating: 200.0, count: 12_001)
        values[347] = 900
        values[348] = 0
        values[9000] = 700
        let metric = makeMetric(values)
        let rendered = metric.chartPoints
        XCTAssertLessThanOrEqual(rendered.count, 600)
        XCTAssertEqual(rendered.first?.timestamp, metric.points.first?.timestamp)
        XCTAssertEqual(rendered.last?.timestamp, metric.points.last?.timestamp)
        for index in [347, 348, 9000] {
            XCTAssertTrue(rendered.contains { $0.timestamp == metric.points[index].timestamp && $0.value == values[index] })
        }
        XCTAssertTrue(zip(rendered, rendered.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        XCTAssertEqual(metric.points.count, 12_001)
        XCTAssertEqual(metric.points.map(\.value), values)
    }

    func testConstantAndJustOverLimitSeriesHaveUniqueOrderedSamples() {
        for count in [601, 12_001] {
            let metric = makeMetric(Array(repeating: 0, count: count))
            let rendered = metric.chartPoints
            XCTAssertLessThanOrEqual(rendered.count, 600)
            XCTAssertEqual(Set(rendered.map(\.timestamp)).count, rendered.count)
            XCTAssertTrue(rendered.allSatisfy { $0.value == 0 })
            XCTAssertEqual(rendered.last?.timestamp, metric.points.last?.timestamp)
        }
    }

    func testSelectionUsesOriginalSampleOmittedFromDenseRendering() throws {
        let metric = makeMetric((0..<12_001).map { Double($0 % 30) })
        let rendered = Set(metric.chartPoints.map(\.timestamp))
        let omitted = try XCTUnwrap(metric.points.first { !rendered.contains($0.timestamp) })
        let selected = try XCTUnwrap(metric.nearestPoint(to: omitted.timestamp.timeIntervalSince1970) { $0.timeIntervalSince1970 })
        XCTAssertEqual(selected.timestamp, omitted.timestamp)
        XCTAssertEqual(selected.value, omitted.value)
        XCTAssertLessThanOrEqual(metric.chartPoints.count, 600)
    }

    func testSelectionSkipsMissingDistanceCoordinatesAndKeepsEarlierTie() throws {
        let metric = makeMetric([10, 20, 30, 40])
        let selected = metric.nearestPoint(to: 1.5) { time in
            let second = time.timeIntervalSince1970
            return second == 1 ? nil : second
        }
        XCTAssertEqual(selected?.value, 30)
        XCTAssertEqual(metric.nearestPoint(to: 1.5) { $0.timeIntervalSince1970 }?.value, 20)
        XCTAssertNil(metric.nearestPoint(to: 1) { _ in nil })
        XCTAssertNil(metric.nearestPoint(to: .nan) { $0.timeIntervalSince1970 })
        XCTAssertNil(makeMetric([]).nearestPoint(to: 0) { $0.timeIntervalSince1970 })
    }

    func testUnitlessValuesDoNotAddWhitespace() {
        XCTAssertEqual(WorkoutFormat.number(120, unit: ""), "120")
        XCTAssertEqual(WorkoutFormat.number(150, unit: "bpm"), "150 bpm")
    }

    func testPreparedProjectionShowsIsolatedSegmentsAndSelectsUndecimatedSamples() throws {
        let times = [0.0, 1, 122, 243, 244]
        let metric = WorkoutMetric(id: "temperature", title: .temperature, unit: "°C", points: times.map {
            MetricPoint(timestamp: Date(timeIntervalSince1970: $0), value: 20)
        })
        let projection = MetricChartProjection(metric: metric) { $0.timeIntervalSince1970 }
        XCTAssertEqual(projection.rendered.map(\.isolated), [false, false, true, false, false])
        let sparse = WorkoutMetric(id: "temperature", title: .temperature, unit: "°C", points: (0..<40).map {
            MetricPoint(timestamp: Date(timeIntervalSince1970: Double($0 * 121)), value: 20)
        })
        XCTAssertTrue(MetricChartProjection(metric: sparse) { $0.timeIntervalSince1970 }.rendered.allSatisfy(\.isolated))
        let dense = makeMetric((0..<14_400).map { Double($0 % 30) })
        var projections = 0
        let prepared = MetricChartProjection(metric: dense) { projections += 1; return $0.timeIntervalSince1970 }
        let omitted = try XCTUnwrap(dense.points.first { sample in !prepared.rendered.contains { $0.id == sample.id } })
        XCTAssertEqual(prepared.nearest(to: omitted.timestamp.timeIntervalSince1970)?.id, omitted.id)
        for x in 0..<100 { _ = prepared.nearest(to: Double(x)) }
        XCTAssertEqual(projections, dense.points.count, "Scrubbing must not recalculate the source coordinates")
    }

    private func makeMetric(_ values: [Double]) -> WorkoutMetric {
        WorkoutMetric(id: "power", title: .power, unit: "W", points: values.enumerated().map {
            MetricPoint(timestamp: Date(timeIntervalSince1970: Double($0.offset)), value: $0.element)
        })
    }
}
