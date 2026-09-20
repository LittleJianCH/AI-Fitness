package com.aifitness

import com.aifitness.contract.*
import java.time.Duration as JavaDuration

fun MetricKind.unit(running: Boolean): String =
    when (this) {
        MetricKind.heartRateMetric -> "bpm"
        MetricKind.powerMetric -> "W"
        MetricKind.speedMetric -> "m/s"
        MetricKind.cadenceMetric -> if (running) "steps/min" else "rpm"
        MetricKind.altitudeMetric,
        MetricKind.stepLengthMetric,
        MetricKind.verticalOscillationMetric -> "m"
        MetricKind.groundContactTimeMetric -> "s"
        MetricKind.temperatureMetric -> "°C"
        MetricKind.gradeMetric -> "%"
    }

fun MetricKind.digits(): Int =
    when (this) {
        MetricKind.stepLengthMetric -> 2
        MetricKind.verticalOscillationMetric,
        MetricKind.groundContactTimeMetric -> 3
        else -> 1
    }

val Workout.running: Boolean
    get() = workoutObservation.observationSport is SportRunning
val Workout.motion: MotionData
    get() =
        when (val sport = workoutObservation.observationSport) {
            is SportCycling -> sport.data.cyclingMotion
            is SportRunning -> sport.data.runningMotion
        }
val Workout.recorded: CommonSummary
    get() =
        when (val sport = workoutObservation.observationSport) {
            is SportCycling -> sport.data.cyclingSummary.recordedSummary.cyclingCommonSummary
            is SportRunning -> sport.data.runningSummary.recordedSummary.runningCommonSummary
        }
val WorkoutCard.recorded: CommonSummary
    get() =
        when (val sport = summary) {
            is SportSummaryCyclingSummary -> sport.data.recordedSummary.cyclingCommonSummary
            is SportSummaryRunningSummary -> sport.data.recordedSummary.runningCommonSummary
        }

/** Coordinates from recorded samples or backend analysis; no domain calculations. */
data class ChartPoint(
    val x: Double,
    val y: Double,
    val label: String,
    val breakBefore: Boolean = false,
    val upperX: Double? = null,
)

/** Logarithmic duration coordinates retain the original seconds for labels and selection. */
fun chartX(value: Double, logarithmic: Boolean): Double =
    if (logarithmic) kotlin.math.ln(value.coerceAtLeast(1.0)) else value

fun isolatedChartPoint(points: List<ChartPoint>, index: Int): Boolean =
    (index == 0 || points[index].breakBefore) &&
        (index == points.lastIndex || points[index + 1].breakBefore)

/** Numeric distributions retain full intervals; zone indices occupy equal category slots. */
fun ChartPoint.barRange(): ClosedFloatingPointRange<Double> =
    upperX?.let { x..it } ?: (x - 0.5)..(x + 0.5)

fun nearestBarIndex(points: List<ChartPoint>, target: Double): Int {
    val containing = points.indexOfFirst {
        target >= it.barRange().start && target < it.barRange().endInclusive
    }
    return if (containing >= 0) containing
    else
        points.indices.minBy { index ->
            val range = points[index].barRange()
            kotlin.math.abs(target - target.coerceIn(range.start, range.endInclusive))
        }
}

/** Navigation remains available from recorded samples when derived analysis fails. */
fun Workout.metricKinds(analysis: WorkoutAnalysis? = null): List<MetricKind> {
    val sport = workoutObservation.observationSport
    val running = (sport as? SportRunning)?.data
    return MetricKind.entries.filter { kind ->
        val hasSamples =
            when (kind) {
                MetricKind.heartRateMetric -> motion.motionHeartRate.isNotEmpty()
                MetricKind.powerMetric -> motion.motionPower.isNotEmpty()
                MetricKind.speedMetric -> motion.motionSpeed.isNotEmpty()
                MetricKind.altitudeMetric -> motion.motionAltitude.isNotEmpty()
                MetricKind.gradeMetric -> motion.motionGrade.isNotEmpty()
                MetricKind.temperatureMetric ->
                    motion.motionEnvironment.ambientTemperature.isNotEmpty()
                MetricKind.cadenceMetric ->
                    when (sport) {
                        is SportCycling -> sport.data.cyclingCadence.isNotEmpty()
                        is SportRunning -> sport.data.runningCadence.isNotEmpty()
                    }
                MetricKind.stepLengthMetric ->
                    running?.runningDynamics?.stepLength?.isNotEmpty() == true
                MetricKind.verticalOscillationMetric ->
                    running?.runningDynamics?.verticalOscillation?.isNotEmpty() == true
                MetricKind.groundContactTimeMetric ->
                    running?.runningDynamics?.groundContactTime?.isNotEmpty() == true
            }
        hasSamples || analysis?.analysisMetrics?.any { it.metricKind == kind } == true
    }
}

fun Workout.metricPoints(kind: MetricKind): List<ChartPoint> {
    val start = parseInstant(workoutObservation.observationRange.rangeStart)
    fun point(time: String, value: Double): ChartPoint {
        val seconds = JavaDuration.between(start, parseInstant(time)).toNanos() / 1_000_000_000.0
        return ChartPoint(seconds, value, time)
    }
    return when (kind) {
        MetricKind.heartRateMetric -> motion.motionHeartRate.map { point(it.timestamp, it.value) }
        MetricKind.powerMetric -> motion.motionPower.map { point(it.timestamp, it.value) }
        MetricKind.speedMetric -> motion.motionSpeed.map { point(it.timestamp, it.value) }
        MetricKind.altitudeMetric -> motion.motionAltitude.map { point(it.timestamp, it.value) }
        MetricKind.gradeMetric -> motion.motionGrade.map { point(it.timestamp, it.value) }
        MetricKind.temperatureMetric ->
            motion.motionEnvironment.ambientTemperature.map { point(it.timestamp, it.value) }
        MetricKind.cadenceMetric ->
            when (val sport = workoutObservation.observationSport) {
                is SportCycling -> sport.data.cyclingCadence.map { point(it.timestamp, it.value) }
                is SportRunning -> sport.data.runningCadence.map { point(it.timestamp, it.value) }
            }
        MetricKind.stepLengthMetric ->
            (workoutObservation.observationSport as? SportRunning)
                ?.data
                ?.runningDynamics
                ?.stepLength
                ?.map { point(it.timestamp, it.value) }
                .orEmpty()
        MetricKind.verticalOscillationMetric ->
            (workoutObservation.observationSport as? SportRunning)
                ?.data
                ?.runningDynamics
                ?.verticalOscillation
                ?.map { point(it.timestamp, it.value) }
                .orEmpty()
        MetricKind.groundContactTimeMetric ->
            (workoutObservation.observationSport as? SportRunning)
                ?.data
                ?.runningDynamics
                ?.groundContactTime
                ?.map { point(it.timestamp, it.value) }
                .orEmpty()
    }
}

/**
 * Bound drawing cost, preserving gap markers from the complete stream. Selection uses raw points.
 */
fun renderingPoints(
    points: List<ChartPoint>,
    max: Int = 800,
    gap: Double? = null,
): List<ChartPoint> {
    require(max > 1)
    if (points.isEmpty()) return emptyList()
    val stride = maxOf(1, (points.size + max - 1) / max)
    val result = mutableListOf<ChartPoint>()
    var breakPending = false
    for (index in points.indices) {
        if (
            index > 0 &&
                (points[index].breakBefore ||
                    (gap != null && points[index].x - points[index - 1].x > gap))
        )
            breakPending = true
        if (index % stride == 0 || index == points.lastIndex) {
            result += points[index].copy(breakBefore = breakPending)
            breakPending = false
        }
    }
    return result
}

/** Convert only chart coordinates against the independently sampled distance stream. */
fun Workout.distanceAxis(points: List<ChartPoint>, maxGap: Double): List<ChartPoint> {
    val start = parseInstant(workoutObservation.observationRange.rangeStart)
    val distances =
        motion.motionDistance.map {
            JavaDuration.between(start, parseInstant(it.timestamp)).toNanos() / 1_000_000_000.0 to
                it.value
        }
    var cursor = 0
    var pendingBreak = false
    val result = mutableListOf<ChartPoint>()
    points.forEachIndexed { index, point ->
        if (index > 0 && point.x - points[index - 1].x > maxGap) pendingBreak = true
        while (cursor < distances.lastIndex && distances[cursor + 1].first <= point.x) {
            val before = distances[cursor]
            val after = distances[cursor + 1]
            // Inspect every crossed distance interval, including exact samples
            // and resets hidden between two points of the other sensor stream.
            if (after.first - before.first > maxGap || after.second < before.second)
                pendingBreak = true
            cursor++
        }
        val left = distances.getOrNull(cursor)
        val right = distances.getOrNull(cursor + 1)
        val distance =
            when {
                left == null -> null
                left.first == point.x -> left.second
                right == null ||
                    point.x < left.first ||
                    point.x > right.first ||
                    right.first - left.first > maxGap ||
                    right.second < left.second -> null
                else ->
                    left.second +
                        (right.second - left.second) *
                            ((point.x - left.first) / (right.first - left.first))
            }
        if (distance == null) pendingBreak = true
        else {
            result +=
                point.copy(x = distance / 1000, breakBefore = pendingBreak || point.breakBefore)
            pendingBreak = false
        }
    }
    return result
}

/** Formatting never changes canonical values or decides the missing-value message. */
fun formatNumber(
    value: Double?,
    unit: String = "",
    digits: Int = 1,
    locale: java.util.Locale,
): String? = value?.let {
    String.format(locale, "%.${digits}f", it) + if (unit.isEmpty()) "" else " $unit"
}

fun MetricKind.formatValue(value: Double?, running: Boolean, locale: java.util.Locale): String? =
    formatNumber(value, unit(running), digits(), locale)

/** The caller supplies presentation locale/zone; the original timestamp stays unchanged. */
fun formatDateTime(value: String, locale: java.util.Locale, zone: java.time.ZoneId): String =
    java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM)
        .withLocale(locale)
        .withZone(zone)
        .format(parseInstant(value))
