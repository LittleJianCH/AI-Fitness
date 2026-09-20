package com.aifitness

import com.aifitness.contract.*
import java.io.File
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ContractTests {
    private fun fixture(name: String): JSONObject =
        JSONObject(File(System.getProperty("fixtureDir", "../../backend/build"), name).readText())

    @Test
    fun responseBudgetRejectsOversizeBeforeJsonDecoding() {
        assertEquals(4 * 1024 * 1024, responseCharacterLimit(256L * 1024 * 1024))
        assertEquals(8 * 1024 * 1024, responseCharacterLimit(Long.MAX_VALUE))
        assertEquals("1234", java.io.StringReader("1234").readTextBounded(4))
        org.junit.Assert.assertThrows(ResponseTooLarge::class.java) {
            java.io.StringReader("12345").readTextBounded(4)
        }
    }

    @Test
    fun backendFixturesDecodeAndRoundTrip() {
        val workout = Workout.fromJson(fixture("workout-response.json"))
        assertEquals(workout, Workout.fromJson(workout.toJson()))
        val list = Page_WorkoutCard.fromJson(fixture("list-response.json"))
        assertTrue(list.items.isNotEmpty())
        val analysis = WorkoutAnalysis.fromJson(fixture("analysis-response.json"))
        assertEquals(analysis, WorkoutAnalysis.fromJson(analysis.toJson()))
        val settings = UserSettings.fromJson(fixture("settings-response.json"))
        assertEquals(settings, UserSettings.fromJson(settings.toJson()))
        val curve = PowerCurve.fromJson(fixture("power-curve-response.json"))
        assertEquals(curve, PowerCurve.fromJson(curve.toJson()))
    }

    @Test
    fun requiredOptionalNullAndUnknownFieldsStayDistinct() {
        val json = fixture("settings-response.json")
        json.put("futureField", "ignored")
        UserSettings.fromJson(json)
        json.remove("settingsRevision")
        rejected { UserSettings.fromJson(json) }
        val statistics = JSONObject().put("averageValue", 0)
        assertEquals(0.0, Statistics_Double.fromJson(statistics).averageValue!!, 0.0)
        assertNull(Statistics_Double.fromJson(JSONObject()).averageValue)
        rejected { Statistics_Double.fromJson(JSONObject().put("averageValue", JSONObject.NULL)) }
        rejected { Statistics_Double.fromJson(JSONObject().put("averageValue", "42")) }
        rejected {
            SoftwareSettings.fromJson(JSONObject().put("softwareAppearance", "futureAppearance"))
        }
    }

    @Test
    fun revisionsRemainExactDecimalStrings() {
        val json = fixture("settings-response.json")
        json.put("settingsRevision", "18446744073709551615")
        assertEquals("18446744073709551615", UserSettings.fromJson(json).settingsRevision)
        for (value in listOf<Any>(1, "01", "-1", "1.0", "1e3", "")) {
            json.put("settingsRevision", value)
            rejected { UserSettings.fromJson(json) }
        }
    }

    @Test
    fun picosecondsDecodeWithoutRejectingValidServerTimes() {
        assertEquals(
            "2026-09-19T00:00:00.123456789Z",
            parseInstant("2026-09-19T00:00:00.123456789123Z").toString(),
        )
    }

    @Test
    fun sparseSegmentsKeepStandaloneMarksAndDurationSpacingIsLogarithmic() {
        val points =
            listOf(
                ChartPoint(0.0, 100.0, "a"),
                ChartPoint(1.0, 101.0, "b"),
                ChartPoint(122.0, 120.0, "c", breakBefore = true),
                ChartPoint(243.0, 130.0, "d", breakBefore = true),
                ChartPoint(244.0, 131.0, "e"),
            )
        assertEquals(
            listOf(false, false, true, false, false),
            points.indices.map { isolatedChartPoint(points, it) },
        )
        val sparse = points.map { it.copy(breakBefore = true) }
        assertTrue(sparse.indices.all { isolatedChartPoint(sparse, it) })
        val durations = listOf(1.0, 10.0, 100.0, 1000.0).map { chartX(it, true) }
        durations.zipWithNext().forEach { (a, b) ->
            assertEquals(kotlin.math.ln(10.0), b - a, 1e-12)
        }
        assertEquals(100.0, chartX(100.0, false), 0.0)
        assertEquals(
            "https://example.test",
            FitnessApi.validateEndpoint("HTTPS://example.test", false),
        )
        assertEquals("http://127.0.0.1", FitnessApi.validateEndpoint("HTTP://127.0.0.1", true))
        rejected { FitnessApi.validateEndpoint("HTTP://example.test", true) }
    }

    @Test
    fun endpointPolicyRejectsCredentialAndRedirectDestinations() {
        assertEquals(
            "https://example.test",
            FitnessApi.validateEndpoint("https://example.test/api/v1/", false),
        )
        assertEquals(
            "http://10.0.2.2:8080",
            FitnessApi.validateEndpoint("http://10.0.2.2:8080", true),
        )
        for (value in
            listOf(
                "http://example.test",
                "https://user:password@example.test",
                "https://example.test?token=x",
                "https://example.test/path",
                "file:///tmp/private",
                "http://127.0.0.1.evil.test",
            )) rejected { FitnessApi.validateEndpoint(value, true) }
        rejected { FitnessApi.validateEndpoint("http://127.0.0.1:8080", false) }
    }

    @Test
    fun calendarUsesDaylightSavingBoundaries() {
        val zone = ZoneId.of("America/New_York")
        for ((date, hours) in listOf("2026-03-08" to 23L, "2026-11-01" to 25L)) {
            val day = trainingCalendar(LocalDate.parse(date), 1, zone, false).single()
            assertEquals(
                hours,
                Duration.between(parseInstant(day.calendarStart), parseInstant(day.calendarEnd))
                    .toHours(),
            )
            assertFalse(day.calendarRecordingComplete)
        }
        val days = trainingCalendar(LocalDate.parse("2026-03-09"), 3, zone, true)
        assertEquals(days[0].calendarEnd, days[1].calendarStart)
        rejected { trainingCalendar(LocalDate.now(), 367, zone, true) }
    }

    @Test
    fun histogramUsesFullIntervalsForSingleAndUnequalWidthBins() {
        val single = ChartPoint(2.8, 2700.0, "speed", upperX = 3.8)
        assertEquals(2.8..3.8, single.barRange())
        assertEquals(0, nearestBarIndex(listOf(single), 3.79))
        val bins = listOf(single, ChartPoint(3.8, 120.0, "speed", upperX = 5.8))
        assertEquals(2.8, bins.minOf { it.barRange().start }, 0.0)
        assertEquals(5.8, bins.maxOf { it.barRange().endInclusive }, 0.0)
        // Inside the first bin, a nearer second lower edge must not steal selection.
        assertEquals(0, nearestBarIndex(bins, 3.7))
        assertEquals(1, nearestBarIndex(bins, 3.8))
        assertEquals(1, nearestBarIndex(bins, 5.8))
        assertEquals(0, nearestBarIndex(bins, 0.0))
        assertEquals(1, nearestBarIndex(bins, 10.0))
        val zero = ChartPoint(0.0, 0.0, "zero duration", upperX = 1.0)
        assertEquals(0.0..1.0, zero.barRange())
    }

    @Test
    fun zoneBarsKeepEqualSlotsAroundCategoryIndices() {
        val zones = (1..7).map { ChartPoint(it.toDouble(), 60.0, "zone") }
        assertEquals(0.5..1.5, zones.first().barRange())
        assertEquals(6.5..7.5, zones.last().barRange())
        assertEquals(1, nearestBarIndex(zones, 1.6))
    }

    @Test
    fun downsamplingPreservesHiddenGapAndFullInput() {
        val source =
            (0..2000).map {
                ChartPoint(it.toDouble() + if (it > 503) 300 else 0, it.toDouble(), "sample")
            }
        val visible = renderingPoints(source, max = 100, gap = 120.0)
        assertTrue(visible.size <= 101)
        assertTrue(visible.any { it.breakBefore })
        assertEquals(source.last().x, visible.last().x, 0.0)
        assertEquals(2001, source.size)
    }

    @Test
    fun independentDistanceSamplesDoNotExtrapolateOrBridgeGaps() {
        val original = Workout.fromJson(fixture("workout-response.json"))
        val start = parseInstant(original.workoutObservation.observationRange.rangeStart)
        val sport = original.workoutObservation.observationSport as SportCycling
        val motion =
            sport.data.cyclingMotion.copy(
                motionDistance =
                    listOf(
                        Timed_Distance(start.toString(), 0.0),
                        Timed_Distance(start.plusSeconds(10).toString(), 100.0),
                        Timed_Distance(start.plusSeconds(300).toString(), 3000.0),
                    )
            )
        val workout =
            original.copy(
                workoutObservation =
                    original.workoutObservation.copy(
                        observationSport =
                            sport.copy(data = sport.data.copy(cyclingMotion = motion))
                    )
            )
        val points =
            workout.distanceAxis(
                listOf(-1.0, 5.0, 20.0, 300.0, 301.0).map { ChartPoint(it, 100.0, "point") },
                120.0,
            )
        assertEquals(2, points.size)
        assertEquals(.05, points.first().x, 1e-9)
        assertTrue(points.last().breakBefore)
    }

    @Test
    fun distanceAxisBreaksAtExactAndHiddenResets() {
        val original = Workout.fromJson(fixture("workout-response.json"))
        val start = parseInstant(original.workoutObservation.observationRange.rangeStart)
        val sport = original.workoutObservation.observationSport as SportCycling
        fun project(
            times: List<Long>,
            values: List<Double>,
            sampleTimes: List<Double>,
        ): List<ChartPoint> {
            val motion =
                sport.data.cyclingMotion.copy(
                    motionDistance =
                        times.zip(values).map { (time, value) ->
                            Timed_Distance(start.plusSeconds(time).toString(), value)
                        }
                )
            val workout =
                original.copy(
                    workoutObservation =
                        original.workoutObservation.copy(
                            observationSport =
                                sport.copy(data = sport.data.copy(cyclingMotion = motion))
                        )
                )
            return workout.distanceAxis(sampleTimes.map { ChartPoint(it, 100.0, "sample") }, 120.0)
        }
        val exact =
            project(
                listOf(0, 10, 20, 30),
                listOf(0.0, 1000.0, 0.0, 1000.0),
                listOf(0.0, 10.0, 20.0, 30.0),
            )
        assertFalse(exact[1].breakBefore)
        assertTrue(exact[2].breakBefore)
        assertFalse(exact[3].breakBefore)
        val hidden =
            project(listOf(0, 10, 20, 30), listOf(0.0, 1000.0, 0.0, 1000.0), listOf(0.0, 30.0))
        assertTrue(hidden.last().breakBefore)
        val gap =
            project(
                listOf(0, 10, 300, 310),
                listOf(0.0, 1000.0, 2000.0, 3000.0),
                listOf(0.0, 10.0, 300.0, 310.0),
            )
        assertTrue(gap[2].breakBefore)
        assertFalse(gap[3].breakBefore)
    }

    @Test
    fun runningMetricPrecisionPreservesObservedValues() {
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            assertEquals("0.45 m", MetricKind.stepLengthMetric.formatValue(0.45, true, Locale.US))
            assertEquals("1.50 m", MetricKind.stepLengthMetric.formatValue(1.5, true, Locale.US))
            assertEquals(
                "0.040 m",
                MetricKind.verticalOscillationMetric.formatValue(0.04, true, Locale.US),
            )
            assertEquals(
                "0.249 s",
                MetricKind.groundContactTimeMetric.formatValue(0.249, true, Locale.US),
            )
        } finally {
            Locale.setDefault(previous)
        }
    }

    @Test
    fun rawMetricNavigationDoesNotRequireAnalysis() {
        val original = Workout.fromJson(fixture("workout-response.json"))
        val sport = original.workoutObservation.observationSport as SportCycling
        val start = original.workoutObservation.observationRange.rangeStart
        val motion =
            sport.data.cyclingMotion.copy(motionHeartRate = listOf(Timed_HeartRate(start, 130.0)))
        val workout =
            original.copy(
                workoutObservation =
                    original.workoutObservation.copy(
                        observationSport =
                            sport.copy(data = sport.data.copy(cyclingMotion = motion))
                    )
            )
        assertTrue(workout.metricKinds(null).contains(MetricKind.heartRateMetric))
        assertEquals(130.0, workout.metricPoints(MetricKind.heartRateMetric).single().y, 0.0)
        assertFalse(workout.metricKinds(null).contains(MetricKind.stepLengthMetric))
    }

    @Test
    fun analysisErrorsHaveActionableMessagesBeforeGenericValidation() {
        assertEquals(
            ClientIssue.AnalysisTooLarge,
            userIssue(ApiFailure(422, "analysis_too_large")),
        )
        assertEquals(
            ClientIssue.AnalysisUnavailable,
            userIssue(ApiFailure(422, "analysis_unavailable")),
        )
        assertEquals(ClientIssue.StaleWorkout, userIssue(StaleWorkoutAnalysis()))
    }

    @Test
    fun issuesKeepUnknownFailuresDistinctFromConnectionErrors() {
        assertEquals(ClientIssue.Unknown, userIssue(ApiFailure(500, "future_code")))
        assertEquals(ClientIssue.Network, userIssue(java.io.IOException("private diagnostics")))
        assertEquals(
            ClientIssue.Unknown,
            userIssue(IllegalArgumentException("private diagnostics")),
        )
        assertEquals(ClientIssue.ResponseTooLarge, userIssue(ResponseTooLarge()))
        try {
            userIssue(kotlinx.coroutines.CancellationException())
            fail("Cancellation must propagate")
        } catch (_: kotlinx.coroutines.CancellationException) {}
        assertEquals("0.0 W", formatNumber(0.0, "W", locale = Locale.US))
        assertNull(formatNumber(null, "W", locale = Locale.US))
        assertEquals("1,5 km", formatNumber(1.5, "km", locale = Locale.GERMANY))
    }

    @Test
    fun timestampLabelsUseLocaleAndLocalZone() {
        val source = "2026-09-05T23:55:32.123456789Z"
        val point = ChartPoint(0.0, 250.0, source)
        assertEquals(
            "Sep 5, 2026, 11:55:32 PM",
            formatDateTime(point.label, Locale.US, java.time.ZoneId.of("UTC")),
        )
        assertEquals(
            "2026年9月6日 上午7:55:32",
            formatDateTime(
                point.label,
                Locale.SIMPLIFIED_CHINESE,
                java.time.ZoneId.of("Asia/Shanghai"),
            ),
        )
        assertEquals(
            "Mar 8, 2026, 3:30:00 AM",
            formatDateTime(
                "2026-03-08T07:30:00Z",
                Locale.US,
                java.time.ZoneId.of("America/New_York"),
            ),
        )
        assertEquals(source, point.label)
        assertEquals(123456789, parseInstant(point.label).nano)
    }

    private fun rejected(block: () -> Unit) {
        try {
            block()
        } catch (_: Exception) {
            return
        }
        fail("Invalid contract input was accepted")
    }
}
