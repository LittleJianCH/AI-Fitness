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
import java.time.LocalDate
import java.time.ZoneId

@Composable
fun HistoryScreen(state: FitnessState, model: FitnessViewModel) {
    var end by remember { mutableStateOf(LocalDate.now().toString()) }
    var count by remember { mutableStateOf("30") }
    var zone by remember { mutableStateOf(ZoneId.systemDefault().id) }
    var complete by remember { mutableStateOf(false) }
    var noPrior by remember { mutableStateOf(false) }
    var priorFitness by remember { mutableStateOf("") }
    var priorFatigue by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<Int?>(null) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.testTag("trainingHistory"),
    ) {
        item {
            SectionCard(stringResource(R.string.history_range)) {
                Field(stringResource(R.string.history_end), end, "history_end") { end = it }
                Field(stringResource(R.string.history_days), count, "history_days") { count = it }
                Field(stringResource(R.string.time_zone), zone, "time_zone") { zone = it }
                Row {
                    Checkbox(
                        complete,
                        { complete = it },
                        modifier = Modifier.testTag("historyComplete"),
                    )
                    Text(stringResource(R.string.history_complete), Modifier.padding(top = 12.dp))
                }
                Text(stringResource(R.string.history_completeness_hint))
                Row {
                    Checkbox(
                        noPrior,
                        { noPrior = it },
                        modifier = Modifier.testTag("historyNoPrior"),
                    )
                    Text(stringResource(R.string.history_no_prior), Modifier.padding(top = 12.dp))
                }
                if (!noPrior) {
                    Field(stringResource(R.string.initial_ctl), priorFitness, "initial_ctl") {
                        priorFitness = it
                    }
                    Field(stringResource(R.string.initial_atl), priorFatigue, "initial_atl") {
                        priorFatigue = it
                    }
                }
                error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
                Button(
                    onClick = {
                        try {
                            fun prior(value: String): Double =
                                value.toDouble().also { require(it.isFinite() && it >= 0) }
                            val request =
                                TrainingHistoryRequest(
                                    historyCalendar =
                                        trainingCalendar(
                                            LocalDate.parse(end),
                                            count.toInt(),
                                            ZoneId.of(zone),
                                            complete,
                                        ),
                                    historyAssumeNoPriorLoad = noPrior,
                                    historyPriorFitness =
                                        if (noPrior) null else prior(priorFitness),
                                    historyPriorFatigue =
                                        if (noPrior) null else prior(priorFatigue),
                                )
                            model.loadHistory(request)
                            error = null
                        } catch (_: Exception) {
                            error = R.string.invalid_history
                        }
                    },
                    enabled = !state.busy,
                    modifier = Modifier.testTag("loadHistory"),
                ) {
                    Text(stringResource(R.string.calculate_history))
                }
            }
        }
        state.history?.let { history ->
            item {
                SectionCard(stringResource(R.string.training_trend)) {
                    Text(history.trainingMethod)
                    Text(
                        stringResource(
                            R.string.history_revision,
                            history.trainingSettingsRevision,
                            number(history.trainingInitialFitness),
                            number(history.trainingInitialFatigue),
                        )
                    )
                    PointChart(
                        historyPoints(history.trainingDays) { it.trainingFitness },
                        stringResource(R.string.fitness_ctl),
                        stringResource(R.string.day),
                        "HRSS",
                    )
                    PointChart(
                        historyPoints(history.trainingDays) { it.trainingFatigue },
                        stringResource(R.string.fatigue_atl),
                        stringResource(R.string.day),
                        "HRSS",
                    )
                    PointChart(
                        historyPoints(history.trainingDays) { it.trainingBalance },
                        stringResource(R.string.balance_tsb),
                        stringResource(R.string.day),
                        "HRSS",
                    )
                    Text(stringResource(R.string.history_gap_hint))
                }
            }
            items(history.trainingDays, key = { it.trainingCalendar.calendarDate }) { day ->
                SectionCard(day.trainingCalendar.calendarDate) {
                    ValueRow(
                        stringResource(R.string.total_load),
                        day.trainingTotalLoad?.let { number(it, "HRSS") }
                            ?: stringResource(R.string.unknown_load),
                    )
                    ValueRow(
                        stringResource(R.string.known_load_count),
                        "${number(day.trainingKnownLoad)} / ${day.trainingWorkoutCount}",
                    )
                    ValueRow(
                        "CTL / ATL / TSB",
                        "${number(day.trainingFitness)} / ${number(day.trainingFatigue)} / ${number(day.trainingBalance)}",
                    )
                    ValueRow(
                        stringResource(R.string.initial_weight),
                        number(day.trainingInitialFitnessWeight * 100, "%"),
                    )
                }
            }
        }
    }
}

private fun historyPoints(
    days: List<TrainingDay>,
    value: (TrainingDay) -> Double?,
): List<ChartPoint> {
    var gap = false
    return days.mapIndexedNotNull { index, day ->
        val y = value(day)
        if (y == null) {
            gap = true
            null
        } else
            ChartPoint(index.toDouble() + 1, y, day.trainingCalendar.calendarDate, gap).also {
                gap = false
            }
    }
}
