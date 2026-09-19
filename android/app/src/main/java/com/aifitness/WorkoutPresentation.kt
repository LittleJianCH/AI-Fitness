package com.aifitness

import com.aifitness.contract.*
import java.time.Duration as JavaDuration
import java.util.Locale

fun number(value: Double?, unit: String = "", digits: Int = 1): String =
    value?.let {
        String.format(Locale.getDefault(), "%.${digits}f", it) +
            if (unit.isEmpty()) "" else " $unit"
    } ?: "暂无数据"

fun MetricKind.title(): String =
    when (this) {
        MetricKind.heartRateMetric -> "心率"
        MetricKind.powerMetric -> "功率"
        MetricKind.speedMetric -> "速度"
        MetricKind.cadenceMetric -> "踏频 / 步频"
        MetricKind.altitudeMetric -> "海拔"
        MetricKind.stepLengthMetric -> "步长"
        MetricKind.verticalOscillationMetric -> "垂直振幅"
        MetricKind.groundContactTimeMetric -> "触地时间"
        MetricKind.temperatureMetric -> "温度"
        MetricKind.gradeMetric -> "坡度"
    }

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

/** Raw observed values only: no interpolation, averages, splits, or load formulas. */
data class ChartPoint(
    val x: Double,
    val y: Double,
    val label: String,
    val breakBefore: Boolean = false,
)

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
        while (cursor < distances.lastIndex && distances[cursor + 1].first <= point.x) cursor++
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

fun pace(speed: Double?): String {
    if (speed == null || speed <= 0) return "暂无数据"
    val seconds = (1000 / speed).toInt()
    return "%d:%02d /km".format(seconds / 60, seconds % 60)
}
