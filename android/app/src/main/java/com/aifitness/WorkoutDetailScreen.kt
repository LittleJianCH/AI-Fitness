package com.aifitness

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.aifitness.contract.*

@Composable
fun WorkoutDetailScreen(state: FitnessState, model: FitnessViewModel) {
    val detail = state.detail
    if (detail == null) {
        if (!state.busy)
            TextButton(
                onClick = { (state.screen as? Screen.Detail)?.let { model.loadDetail(it.id) } }
            ) {
                Text(stringResource(R.string.reload_detail))
            }
        return
    }
    val workout = detail.workout
    val analysis = detail.analysis
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.testTag("workoutDetail"),
    ) {
        item {
            Text(
                workout.workoutUserData.workoutTitle
                    ?: if (workout.running) stringResource(R.string.running)
                    else stringResource(R.string.cycling),
                style = MaterialTheme.typography.headlineMedium,
            )
        }
        item { RouteCard(workout, analysis?.analysisMaxGapSeconds?.toDouble() ?: 120.0) }
        item {
            SectionCard(stringResource(R.string.recorded_overview)) {
                ValueRow(
                    stringResource(R.string.start_time),
                    dateTime(workout.workoutObservation.observationRange.rangeStart),
                )
                ValueRow(
                    stringResource(R.string.distance),
                    number(workout.recorded.summaryDistance?.div(1000), "km"),
                )
                ValueRow(
                    stringResource(R.string.timer_moving),
                    "${number(workout.recorded.summaryTimerTime, "s")} / ${number(workout.recorded.summaryMovingTime, "s")}",
                )
                ValueRow(
                    stringResource(R.string.elapsed_time),
                    number(workout.recorded.summaryElapsedTime, "s"),
                )
                ValueRow(
                    stringResource(R.string.ascent_descent),
                    "${number(workout.recorded.summaryAscent, "m")} / ${number(workout.recorded.summaryDescent, "m")}",
                )
                ValueRow(
                    stringResource(R.string.metabolic_energy),
                    number(workout.recorded.summaryMetabolicEnergy, "J"),
                )
            }
        }
        if (analysis == null)
            item {
                SectionCard(stringResource(R.string.metric_analysis)) {
                    Text(
                        if (detail.analysisLoading) stringResource(R.string.calculating_metrics)
                        else
                            detail.analysisError?.text()
                                ?: stringResource(R.string.analysis_unavailable)
                    )
                    if (!detail.analysisLoading)
                        TextButton(onClick = model::retryAnalysis, enabled = !state.busy) {
                            Text(stringResource(R.string.retry_analysis))
                        }
                    TextButton(
                        onClick = { model.loadDetail(workout.workoutId) },
                        enabled = !state.busy,
                    ) {
                        Text(stringResource(R.string.refresh_detail))
                    }
                }
            }
        items(workout.metricKinds(analysis), key = { it.wire }) { kind ->
            val metric = analysis?.analysisMetrics?.firstOrNull { it.metricKind == kind }
            Card(
                onClick = { model.navigate(Screen.Metric(kind)) },
                modifier = Modifier.fillMaxWidth().testTag("metric-${kind.wire}"),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(kind.title(), style = MaterialTheme.typography.titleLarge)
                    if (metric != null) {
                        ValueRow(
                            stringResource(R.string.calculated_average),
                            metric.metricKind.format(
                                metric.metricStatistics.averageValue,
                                workout.running,
                            ),
                        )
                        ValueRow(
                            stringResource(R.string.range),
                            "${metric.metricKind.format(metric.metricStatistics.minimumValue, workout.running)} – ${metric.metricKind.format(metric.metricStatistics.maximumValue, workout.running)}",
                        )
                    } else Text(stringResource(R.string.raw_samples_hint))
                    Text(
                        stringResource(R.string.view_metric),
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
        item { PowerSection(detail, state.busy, model) }
        analysis?.analysisRunning?.let { running ->
            item {
                SectionCard(stringResource(R.string.running_dynamics)) {
                    ValueRow(
                        stringResource(R.string.steps),
                        number(running.runningSteps, digits = 0),
                    )
                    ValueRow(
                        stringResource(R.string.flight_time),
                        number(running.runningFlightSeconds, "s", 3),
                    )
                    ValueRow(
                        stringResource(R.string.flight_ratio),
                        number(running.runningFlightRatioPercent, "%"),
                    )
                    ValueRow(
                        stringResource(R.string.vertical_ratio),
                        number(running.runningVerticalRatioPercent, "%"),
                    )
                    ValueRow(
                        stringResource(R.string.running_effectiveness),
                        number(running.runningEffectiveness),
                    )
                }
            }
        }
        if (analysis != null)
            item {
                SectionCard(stringResource(R.string.heart_load)) {
                    val heart = analysis.analysisHeart
                    ValueRow(
                        stringResource(R.string.status),
                        when (heart.heartLoadStatus) {
                            HeartLoadStatus.heartLoadAvailable ->
                                stringResource(R.string.load_available)
                            HeartLoadStatus.heartProfileMissing ->
                                stringResource(R.string.heart_profile_missing)
                            HeartLoadStatus.heartCoverageInsufficient ->
                                stringResource(R.string.heart_coverage_insufficient)
                            HeartLoadStatus.heartNoActiveTime ->
                                stringResource(R.string.no_active_time)
                            HeartLoadStatus.heartExcluded -> stringResource(R.string.excluded)
                            HeartLoadStatus.heartCalculationUnavailable ->
                                stringResource(R.string.calculation_unavailable)
                        },
                    )
                    ValueRow("HRSS", number(heart.heartHrss))
                    ValueRow("TRIMPexp", number(heart.heartTrimp))
                    ValueRow(
                        stringResource(R.string.coverage),
                        number(heart.heartCoverageFraction?.times(100), "%"),
                    )
                    ValueRow(
                        stringResource(R.string.covered_active),
                        "${number(heart.heartCoveredSeconds, "s")} / ${number(heart.heartActiveSeconds, "s")}",
                    )
                    Text(
                        if (heart.heartUsesRecordedTimer)
                            stringResource(R.string.recorded_timer_hint)
                        else stringResource(R.string.fallback_timer_hint)
                    )
                    Zones(heart.heartZones, stringResource(R.string.heart_zones), "bpm")
                    TextButton(onClick = { model.navigate(Screen.History) }) {
                        Text(stringResource(R.string.view_history))
                    }
                }
            }
        analysis?.analysisSplits.orEmpty().forEach { set ->
            item {
                Text(
                    stringResource(
                        R.string.split_length,
                        number(set.splitLengthMetres / 1000, "km"),
                    ),
                    style = MaterialTheme.typography.titleLarge,
                )
            }
            if (set.distanceSplits.isEmpty()) {
                item { Text(stringResource(R.string.empty_splits)) }
            }
            items(set.distanceSplits, key = { "${set.splitLengthMetres}-${it.splitIndex}" }) { split
                ->
                SectionCard(
                    stringResource(
                        R.string.split_title,
                        split.splitIndex,
                        number(split.splitDistanceMetres, "m"),
                    )
                ) {
                    ValueRow(
                        stringResource(R.string.start_end),
                        "${number(split.splitStartSeconds, "s")} / ${number(split.splitEndSeconds, "s")}",
                    )
                    ValueRow(
                        if (workout.running) stringResource(R.string.pace)
                        else stringResource(R.string.speed),
                        if (workout.running) pace(split.splitAverageSpeed)
                        else number(split.splitAverageSpeed, "m/s"),
                    )
                    ValueRow(
                        stringResource(R.string.heart_power),
                        "${number(split.splitHeartRate, "bpm")} / ${number(split.splitPower, "W")}",
                    )
                    ValueRow(
                        stringResource(R.string.running_cycling_cadence),
                        number(split.splitCadence, if (workout.running) "steps/min" else "rpm"),
                    )
                    ValueRow(
                        stringResource(R.string.elevation_change),
                        number(split.splitElevationChange, "m"),
                    )
                }
            }
        }
        analysis?.analysisHalves?.let { halves ->
            item {
                SectionCard(stringResource(R.string.halves)) {
                    ValueRow(
                        stringResource(R.string.first_half_speed),
                        number(halves.firstHalfSpeed, "m/s"),
                    )
                    ValueRow(
                        stringResource(R.string.second_half_speed),
                        number(halves.secondHalfSpeed, "m/s"),
                    )
                    ValueRow(
                        stringResource(R.string.change),
                        number(halves.secondHalfChangePercent, "%"),
                    )
                }
            }
        }
        item { SourceSection(workout) }
        if (analysis != null)
            item {
                SectionCard(stringResource(R.string.analysis_notes)) {
                    Text(stringResource(R.string.method, analysis.analysisMethod))
                    Text(
                        stringResource(
                            R.string.analysis_revisions,
                            analysis.analysisRevision,
                            analysis.analysisSettingsRevision,
                        )
                    )
                    Text(stringResource(R.string.analysis_gap, analysis.analysisMaxGapSeconds))
                    analysis.analysisNotes.forEach { Text(it) }
                }
            }
    }
}

@Composable
private fun PowerSection(detail: Detail, busy: Boolean, model: FitnessViewModel) {
    val power = detail.analysis?.analysisPower
    SectionCard(stringResource(R.string.power_analysis)) {
        if (power != null) {
            ValueRow(stringResource(R.string.normalized_power), number(power.powerNormalized, "W"))
            ValueRow(
                stringResource(R.string.normalization_time),
                number(power.powerNormalizationSeconds, "s"),
            )
            ValueRow(
                stringResource(R.string.variability_intensity),
                "${number(power.powerVariabilityIndex)} / ${number(power.powerIntensityFactor)}",
            )
            ValueRow(stringResource(R.string.stress), number(power.powerStressScore))
            ValueRow(stringResource(R.string.mechanical_work), number(power.powerWorkJoules, "J"))
            ValueRow(
                stringResource(R.string.watts_per_kg),
                number(power.powerWattsPerKilogram, "W/kg"),
            )
            ValueRow(
                stringResource(R.string.efficiency_decoupling),
                "${number(power.powerEfficiency)} / ${number(power.powerDecouplingPercent, "%")}",
            )
            ValueRow(
                stringResource(R.string.used_ftp_mass),
                "${number(power.powerThresholdWatts, "W")} / ${number(power.powerAthleteKilograms, "kg")}",
            )
            Zones(
                detail.analysis?.analysisPowerZones.orEmpty(),
                stringResource(R.string.power_zones),
                "W",
            )
        }
        val curve = detail.curve
        if (curve != null) {
            val points =
                curve.points.mapNotNull { point ->
                    point.best?.let {
                        ChartPoint(
                            point.durationSeconds.toDouble(),
                            it.averagePower,
                            "${it.start} – ${it.end}",
                        )
                    }
                }
            val intervals = curve.points.mapNotNull { it.best }
            PointChart(
                points,
                stringResource(R.string.power_curve),
                "s",
                "W",
                logarithmicX = true,
                selectedLabel = { index ->
                    val interval = intervals[index]
                    "${dateTime(interval.start)} – ${dateTime(interval.end)}"
                },
            )
            Text(stringResource(R.string.curve_method, curve.method, curve.maxGapSeconds))
            val missing = curve.points.filter { it.best == null }
            if (missing.isNotEmpty())
                Text(
                    stringResource(
                        R.string.curve_missing,
                        missing.joinToString { "${it.durationSeconds}s" },
                    )
                )
        } else {
            Text(
                if (detail.curveLoading) stringResource(R.string.loading_curve)
                else detail.curveError?.text() ?: stringResource(R.string.curve_unavailable)
            )
            if (!detail.curveLoading)
                TextButton(onClick = model::retryCurve, enabled = !busy) {
                    Text(stringResource(R.string.retry_curve))
                }
        }
    }
}

@Composable
fun Zones(zones: List<ZoneDuration>, title: String, unit: String) {
    if (zones.isEmpty()) Text(stringResource(R.string.zones_missing, title))
    else
        PointChart(
            zones.map {
                ChartPoint(
                    it.zoneIndex.toDouble(),
                    it.zoneSeconds,
                    "${number(it.zoneLower, unit)} – ${it.zoneUpper?.let { upper -> number(upper, unit) } ?: stringResource(R.string.and_above)}",
                )
            },
            title,
            stringResource(R.string.zone),
            "s",
            bars = true,
        )
}

@Composable
private fun SourceSection(workout: Workout) {
    SectionCard(stringResource(R.string.source_context)) {
        Text(stringResource(R.string.source_context_hint))
        ValueRow(
            stringResource(R.string.recorded_altitude),
            "${number(workout.recorded.summaryAltitude.averageValue, "m")} / ${number(workout.recorded.summaryAltitude.minimumValue, "m")} / ${number(workout.recorded.summaryAltitude.maximumValue, "m")}",
        )
        ValueRow(
            stringResource(R.string.recorded_work),
            number(workout.recorded.summaryMechanicalWork, "J"),
        )
        when (val sport = workout.workoutObservation.observationSport) {
            is SportCycling -> {
                ValueRow(
                    stringResource(R.string.bicycle),
                    sport.data.cyclingContext.bicycleName ?: stringResource(R.string.not_recorded),
                )
                ValueRow(
                    stringResource(R.string.bicycle_mass),
                    number(sport.data.cyclingContext.bicycleMass, "kg"),
                )
                if (sport.data.cyclingLaps.isEmpty()) Text(stringResource(R.string.empty_laps))
                sport.data.cyclingLaps.forEachIndexed { index, lap ->
                    Text(
                        lap.lapLabel ?: stringResource(R.string.source_lap, index + 1),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "${dateTime(lap.lapRange.rangeStart)} – ${dateTime(lap.lapRange.rangeEnd)}"
                    )
                    ValueRow(
                        stringResource(R.string.recorded_distance_timer),
                        "${number(lap.lapSummary.recordedSummary.cyclingCommonSummary.summaryDistance, "m")} / ${number(lap.lapSummary.recordedSummary.cyclingCommonSummary.summaryTimerTime, "s")}",
                    )
                }
            }
            is SportRunning -> {
                if (sport.data.runningLaps.isEmpty()) Text(stringResource(R.string.empty_laps))
                sport.data.runningLaps.forEachIndexed { index, lap ->
                    Text(
                        lap.lapLabel ?: stringResource(R.string.source_lap, index + 1),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "${dateTime(lap.lapRange.rangeStart)} – ${dateTime(lap.lapRange.rangeEnd)}"
                    )
                    ValueRow(
                        stringResource(R.string.recorded_distance_timer),
                        "${number(lap.lapSummary.recordedSummary.runningCommonSummary.summaryDistance, "m")} / ${number(lap.lapSummary.recordedSummary.runningCommonSummary.summaryTimerTime, "s")}",
                    )
                }
            }
        }
        workout.workoutUserData.workoutNotes?.let { Text(it) }
        Text(workout.workoutUserData.workoutTags.joinToString(" · "))
    }
}

@Composable
fun MetricScreen(detail: Detail?, kind: MetricKind) {
    if (detail == null) {
        Text(stringResource(R.string.reopen_workout))
        return
    }
    val workout = detail.workout
    val analysis = detail.analysis
    val metric = analysis?.analysisMetrics?.firstOrNull { it.metricKind == kind }
    var distance by remember(kind) { mutableStateOf(false) }
    val raw = remember(workout, kind) { workout.metricPoints(kind) }
    val gap = analysis?.analysisMaxGapSeconds?.toDouble() ?: 120.0
    val points =
        remember(raw, distance, gap) { if (distance) workout.distanceAxis(raw, gap) else raw }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.testTag("metricScreen"),
    ) {
        item {
            SectionCard(kind.title()) {
                Row {
                    FilterChip(
                        distance,
                        { distance = true },
                        label = { Text(stringResource(R.string.distance)) },
                    )
                    Spacer(Modifier.width(8.dp))
                    FilterChip(
                        !distance,
                        { distance = false },
                        label = { Text(stringResource(R.string.time)) },
                    )
                }
                PointChart(
                    points,
                    kind.title(),
                    if (distance) "km" else "s",
                    kind.unit(workout.running),
                    if (distance) null else gap,
                    yDigits = kind.digits(),
                    selectedLabel = { index -> dateTime(points[index].label) },
                )
                Text(stringResource(R.string.raw_selection_hint))
                if (analysis == null)
                    Text(
                        detail.analysisError?.text()
                            ?: stringResource(R.string.metric_unavailable_hint)
                    )
            }
        }
        metric?.let {
            item {
                SectionCard(stringResource(R.string.calculated_statistics)) {
                    ValueRow(
                        stringResource(R.string.average),
                        kind.format(it.metricStatistics.averageValue, workout.running),
                    )
                    if (workout.running && kind == MetricKind.speedMetric)
                        ValueRow(
                            stringResource(R.string.average_pace),
                            pace(it.metricStatistics.averageValue),
                        )
                    ValueRow(
                        stringResource(R.string.minimum_maximum),
                        "${kind.format(it.metricStatistics.minimumValue, workout.running)} / ${kind.format(it.metricStatistics.maximumValue, workout.running)}",
                    )
                    ValueRow(
                        stringResource(R.string.average_without_zeros),
                        kind.format(it.metricAverageExcludingZeros, workout.running),
                    )
                    ValueRow(
                        stringResource(R.string.samples_coverage),
                        "${it.metricSampleCount} / ${number(it.metricCoveredSeconds, "s")}",
                    )
                    PointChart(
                        it.metricDistribution.map { bin ->
                            ChartPoint(
                                bin.binLower,
                                bin.binSeconds,
                                "${kind.format(bin.binLower, workout.running)} – ${kind.format(bin.binUpper, workout.running)}",
                                upperX = bin.binUpper,
                            )
                        },
                        stringResource(R.string.distribution),
                        kind.unit(workout.running),
                        "s",
                        bars = true,
                        xDigits = kind.digits(),
                    )
                }
            }
        }
        items(
            analysis?.analysisRelationships.orEmpty().filter {
                it.relationshipX == kind || it.relationshipY == kind
            }
        ) { relationship ->
            SectionCard(
                "${relationship.relationshipX.title()} / ${relationship.relationshipY.title()}"
            ) {
                ValueRow(
                    stringResource(R.string.correlation_samples),
                    "${number(relationship.relationshipCorrelation, digits = 3)} / ${relationship.relationshipSampleCount}",
                )
                PointChart(
                    relationship.relationshipPoints.map {
                        ChartPoint(
                            it.relationshipXValue,
                            it.relationshipYValue,
                            stringResource(R.string.aligned_sample),
                        )
                    },
                    stringResource(R.string.relationship),
                    relationship.relationshipX.unit(workout.running),
                    relationship.relationshipY.unit(workout.running),
                    scatter = true,
                    xDigits = relationship.relationshipX.digits(),
                    yDigits = relationship.relationshipY.digits(),
                )
            }
        }
    }
}
