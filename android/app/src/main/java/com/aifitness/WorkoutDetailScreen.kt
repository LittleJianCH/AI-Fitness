package com.aifitness

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
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
                Text("重新加载运动详情")
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
                workout.workoutUserData.workoutTitle ?: if (workout.running) "跑步" else "骑行",
                style = MaterialTheme.typography.headlineMedium,
            )
        }
        item { RouteCard(workout, analysis?.analysisMaxGapSeconds?.toDouble() ?: 120.0) }
        item {
            SectionCard("运动概览 · 设备记录") {
                ValueRow("开始时间", workout.workoutObservation.observationRange.rangeStart)
                ValueRow("距离", number(workout.recorded.summaryDistance?.div(1000), "km"))
                ValueRow(
                    "计时 / 移动",
                    "${number(workout.recorded.summaryTimerTime, "s")} / ${number(workout.recorded.summaryMovingTime, "s")}",
                )
                ValueRow("经过时间", number(workout.recorded.summaryElapsedTime, "s"))
                ValueRow(
                    "爬升 / 下降",
                    "${number(workout.recorded.summaryAscent, "m")} / ${number(workout.recorded.summaryDescent, "m")}",
                )
                ValueRow("代谢能量", number(workout.recorded.summaryMetabolicEnergy, "J"))
            }
        }
        if (analysis == null)
            item {
                SectionCard("指标分析") {
                    Text(
                        if (detail.analysisLoading) "正在计算指标…" else detail.analysisError ?: "分析暂不可用"
                    )
                    if (!detail.analysisLoading)
                        TextButton(onClick = model::retryAnalysis, enabled = !state.busy) {
                            Text("重试指标分析")
                        }
                    TextButton(
                        onClick = { model.loadDetail(workout.workoutId) },
                        enabled = !state.busy,
                    ) {
                        Text("刷新运动详情")
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
                            "后端计算均值",
                            metric.metricKind.format(
                                metric.metricStatistics.averageValue,
                                workout.running,
                            ),
                        )
                        ValueRow(
                            "范围",
                            "${metric.metricKind.format(metric.metricStatistics.minimumValue, workout.running)} – ${metric.metricKind.format(metric.metricStatistics.maximumValue, workout.running)}",
                        )
                    } else Text("原始样本可用，后端统计暂不可用。")
                    Text("查看曲线、分布与关系 →", color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        item { PowerSection(detail, state.busy, model) }
        analysis?.analysisRunning?.let { running ->
            item {
                SectionCard("跑步动态 · 后端计算") {
                    ValueRow("步数", number(running.runningSteps, digits = 0))
                    ValueRow("腾空时间", number(running.runningFlightSeconds, "s", 3))
                    ValueRow("腾空比例", number(running.runningFlightRatioPercent, "%"))
                    ValueRow("垂直比", number(running.runningVerticalRatioPercent, "%"))
                    ValueRow("跑步效能", number(running.runningEffectiveness))
                }
            }
        }
        if (analysis != null)
            item {
                SectionCard("心率负荷") {
                    val heart = analysis.analysisHeart
                    ValueRow(
                        "状态",
                        when (heart.heartLoadStatus) {
                            HeartLoadStatus.heartLoadAvailable -> "负荷可用"
                            HeartLoadStatus.heartProfileMissing -> "缺少心率参数"
                            HeartLoadStatus.heartCoverageInsufficient -> "心率覆盖不足；显示已观测部分"
                            HeartLoadStatus.heartNoActiveTime -> "没有活动计时时长"
                            HeartLoadStatus.heartExcluded -> "已排除统计"
                            HeartLoadStatus.heartCalculationUnavailable -> "当前数据无法计算"
                        },
                    )
                    ValueRow("HRSS", number(heart.heartHrss))
                    ValueRow("TRIMPexp", number(heart.heartTrimp))
                    ValueRow("覆盖率", number(heart.heartCoverageFraction?.times(100), "%"))
                    ValueRow(
                        "覆盖 / 活动时长",
                        "${number(heart.heartCoveredSeconds, "s")} / ${number(heart.heartActiveSeconds, "s")}",
                    )
                    Text(if (heart.heartUsesRecordedTimer) "使用记录的计时区间。" else "没有计时事件，使用标注的经过时间回退。")
                    Zones(heart.heartZones, "心率区间", "bpm")
                    TextButton(onClick = { model.navigate(Screen.History) }) { Text("查看训练历史") }
                }
            }
        analysis?.analysisSplits.orEmpty().forEach { set ->
            item {
                Text(
                    "${number(set.splitLengthMetres / 1000, "km")} 分段",
                    style = MaterialTheme.typography.titleLarge,
                )
            }
            items(set.distanceSplits, key = { "${set.splitLengthMetres}-${it.splitIndex}" }) { split
                ->
                SectionCard("第 ${split.splitIndex} 段 · ${number(split.splitDistanceMetres, "m")}") {
                    ValueRow(
                        "开始 / 结束",
                        "${number(split.splitStartSeconds, "s")} / ${number(split.splitEndSeconds, "s")}",
                    )
                    ValueRow(
                        if (workout.running) "配速" else "速度",
                        if (workout.running) pace(split.splitAverageSpeed)
                        else number(split.splitAverageSpeed, "m/s"),
                    )
                    ValueRow(
                        "心率 / 功率",
                        "${number(split.splitHeartRate, "bpm")} / ${number(split.splitPower, "W")}",
                    )
                    ValueRow(
                        "步频 / 踏频",
                        number(split.splitCadence, if (workout.running) "steps/min" else "rpm"),
                    )
                    ValueRow("海拔变化", number(split.splitElevationChange, "m"))
                }
            }
        }
        analysis?.analysisHalves?.let { halves ->
            item {
                SectionCard("前后半程比较") {
                    ValueRow("前半程速度", number(halves.firstHalfSpeed, "m/s"))
                    ValueRow("后半程速度", number(halves.secondHalfSpeed, "m/s"))
                    ValueRow("变化", number(halves.secondHalfChangePercent, "%"))
                }
            }
        }
        item { SourceSection(workout) }
        if (analysis != null)
            item {
                SectionCard("分析说明") {
                    Text("方法：${analysis.analysisMethod}")
                    Text(
                        "运动版本 ${analysis.analysisRevision} · 参数版本 ${analysis.analysisSettingsRevision}"
                    )
                    Text("指标长间隔阈值 ${analysis.analysisMaxGapSeconds}s；缺失数据不等于零。")
                    analysis.analysisNotes.forEach { Text(it) }
                }
            }
    }
}

@Composable
private fun PowerSection(detail: Detail, busy: Boolean, model: FitnessViewModel) {
    val power = detail.analysis?.analysisPower
    SectionCard("功率分析") {
        if (power != null) {
            ValueRow("标准化功率", number(power.powerNormalized, "W"))
            ValueRow("有效标准化时长", number(power.powerNormalizationSeconds, "s"))
            ValueRow(
                "变异指数 / 强度因子",
                "${number(power.powerVariabilityIndex)} / ${number(power.powerIntensityFactor)}",
            )
            ValueRow("训练压力", number(power.powerStressScore))
            ValueRow("机械功", number(power.powerWorkJoules, "J"))
            ValueRow("功率体重比", number(power.powerWattsPerKilogram, "W/kg"))
            ValueRow(
                "效率 / 解耦",
                "${number(power.powerEfficiency)} / ${number(power.powerDecouplingPercent, "%")}",
            )
            ValueRow(
                "使用的 FTP / 体重",
                "${number(power.powerThresholdWatts, "W")} / ${number(power.powerAthleteKilograms, "kg")}",
            )
            Zones(detail.analysis?.analysisPowerZones.orEmpty(), "功率区间", "W")
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
            PointChart(points, "功率持续时间曲线", "s", "W")
            Text("${curve.method} · 间隔上限 ${curve.maxGapSeconds}s")
            val missing = curve.points.filter { it.best == null }
            if (missing.isNotEmpty())
                Text("无完整覆盖：${missing.joinToString { "${it.durationSeconds}s" }}")
        } else {
            Text(if (detail.curveLoading) "正在加载功率曲线…" else detail.curveError ?: "功率曲线暂不可用")
            if (!detail.curveLoading)
                TextButton(onClick = model::retryCurve, enabled = !busy) { Text("重试功率曲线") }
        }
    }
}

@Composable
fun Zones(zones: List<ZoneDuration>, title: String, unit: String) {
    if (zones.isEmpty()) Text("$title：缺少参数或覆盖数据")
    else
        PointChart(
            zones.map {
                ChartPoint(
                    it.zoneIndex.toDouble(),
                    it.zoneSeconds,
                    "${number(it.zoneLower, unit)} – ${it.zoneUpper?.let { upper -> number(upper, unit) } ?: "以上"}",
                )
            },
            title,
            "区",
            "s",
            bars = true,
        )
}

@Composable
private fun SourceSection(workout: Workout) {
    SectionCard("来源记录与上下文") {
        Text("以下为源记录中的圈与汇总，与计算分段、计算指标分别展示。")
        ValueRow(
            "记录海拔均值 / 最低 / 最高",
            "${number(workout.recorded.summaryAltitude.averageValue, "m")} / ${number(workout.recorded.summaryAltitude.minimumValue, "m")} / ${number(workout.recorded.summaryAltitude.maximumValue, "m")}",
        )
        ValueRow("记录机械功", number(workout.recorded.summaryMechanicalWork, "J"))
        when (val sport = workout.workoutObservation.observationSport) {
            is SportCycling -> {
                ValueRow("自行车", sport.data.cyclingContext.bicycleName ?: "暂无数据")
                ValueRow("自行车质量", number(sport.data.cyclingContext.bicycleMass, "kg"))
                if (sport.data.cyclingLaps.isEmpty()) Text("无源圈记录")
                sport.data.cyclingLaps.forEachIndexed { index, lap ->
                    Text(
                        lap.lapLabel ?: "源圈 ${index + 1}",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text("${lap.lapRange.rangeStart} – ${lap.lapRange.rangeEnd}")
                    ValueRow(
                        "记录距离 / 计时",
                        "${number(lap.lapSummary.recordedSummary.cyclingCommonSummary.summaryDistance, "m")} / ${number(lap.lapSummary.recordedSummary.cyclingCommonSummary.summaryTimerTime, "s")}",
                    )
                }
            }
            is SportRunning -> {
                if (sport.data.runningLaps.isEmpty()) Text("无源圈记录")
                sport.data.runningLaps.forEachIndexed { index, lap ->
                    Text(
                        lap.lapLabel ?: "源圈 ${index + 1}",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text("${lap.lapRange.rangeStart} – ${lap.lapRange.rangeEnd}")
                    ValueRow(
                        "记录距离 / 计时",
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
        Text("请重新打开运动以加载最新分析。")
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
    ) {
        item {
            SectionCard(kind.title()) {
                Row {
                    FilterChip(distance, { distance = true }, label = { Text("距离") })
                    Spacer(Modifier.width(8.dp))
                    FilterChip(!distance, { distance = false }, label = { Text("时间") })
                }
                PointChart(
                    points,
                    kind.title(),
                    if (distance) "km" else "s",
                    kind.unit(workout.running),
                    if (distance) null else gap,
                    yDigits = kind.digits(),
                )
                Text("选点来自原始样本。距离轴仅映射有效距离区间，不跨间隔推算。")
                if (analysis == null) Text(detail.analysisError ?: "后端统计暂不可用，返回详情页可重试。")
            }
        }
        metric?.let {
            item {
                SectionCard("统计 · 后端计算") {
                    ValueRow(
                        "均值",
                        kind.format(it.metricStatistics.averageValue, workout.running),
                    )
                    if (workout.running && kind == MetricKind.speedMetric)
                        ValueRow("平均配速", pace(it.metricStatistics.averageValue))
                    ValueRow(
                        "最小 / 最大",
                        "${kind.format(it.metricStatistics.minimumValue, workout.running)} / ${kind.format(it.metricStatistics.maximumValue, workout.running)}",
                    )
                    ValueRow(
                        "排除零均值",
                        kind.format(it.metricAverageExcludingZeros, workout.running),
                    )
                    ValueRow(
                        "样本 / 覆盖",
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
                        "分布",
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
                    "相关系数 / 对齐样本",
                    "${number(relationship.relationshipCorrelation, digits = 3)} / ${relationship.relationshipSampleCount}",
                )
                PointChart(
                    relationship.relationshipPoints.map {
                        ChartPoint(it.relationshipXValue, it.relationshipYValue, "后端对齐样本")
                    },
                    "关系",
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
