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
    var error by remember { mutableStateOf<String?>(null) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.testTag("trainingHistory"),
    ) {
        item {
            SectionCard("历史范围") {
                Field("结束日期 (YYYY-MM-DD)", end) { end = it }
                Field("天数 (1–366)", count) { count = it }
                Field("时区", zone) { zone = it }
                Row {
                    Checkbox(
                        complete,
                        { complete = it },
                        modifier = Modifier.testTag("historyComplete"),
                    )
                    Text("确认这段时间的运动记录完整", Modifier.padding(top = 12.dp))
                }
                Text("未确认完整的空白日期保持未知；确认完整的空白日期才视为休息。跨夏令时使用真实本地日边界。")
                Row {
                    Checkbox(
                        noPrior,
                        { noPrior = it },
                        modifier = Modifier.testTag("historyNoPrior"),
                    )
                    Text("明确假设此前无训练负荷", Modifier.padding(top = 12.dp))
                }
                if (!noPrior) {
                    Field("初始 CTL (HRSS)", priorFitness) { priorFitness = it }
                    Field("初始 ATL (HRSS)", priorFatigue) { priorFatigue = it }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
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
                            error = "请检查日期、时区、1–366 天范围，以及非负的初始 CTL / ATL。"
                        }
                    },
                    enabled = !state.busy,
                    modifier = Modifier.testTag("loadHistory"),
                ) {
                    Text("计算训练历史")
                }
            }
        }
        state.history?.let { history ->
            item {
                SectionCard("训练趋势 · 后端计算") {
                    Text(history.trainingMethod)
                    Text(
                        "参数版本 ${history.trainingSettingsRevision} · 初始 CTL ${number(history.trainingInitialFitness)} / ATL ${number(history.trainingInitialFatigue)}"
                    )
                    PointChart(
                        historyPoints(history.trainingDays) { it.trainingFitness },
                        "适能 CTL",
                        "日",
                        "HRSS",
                    )
                    PointChart(
                        historyPoints(history.trainingDays) { it.trainingFatigue },
                        "疲劳 ATL",
                        "日",
                        "HRSS",
                    )
                    PointChart(
                        historyPoints(history.trainingDays) { it.trainingBalance },
                        "状态 TSB",
                        "日",
                        "HRSS",
                    )
                    Text("未知日期不会连线；不足覆盖的负荷不会按比例补齐。")
                }
            }
            items(history.trainingDays, key = { it.trainingCalendar.calendarDate }) { day ->
                SectionCard(day.trainingCalendar.calendarDate) {
                    ValueRow(
                        "总负荷",
                        day.trainingTotalLoad?.let { number(it, "HRSS") } ?: "未知：记录或覆盖不完整",
                    )
                    ValueRow(
                        "已知部分 / 运动数",
                        "${number(day.trainingKnownLoad)} / ${day.trainingWorkoutCount}",
                    )
                    ValueRow(
                        "CTL / ATL / TSB",
                        "${number(day.trainingFitness)} / ${number(day.trainingFatigue)} / ${number(day.trainingBalance)}",
                    )
                    ValueRow("初始 CTL 剩余权重", number(day.trainingInitialFitnessWeight * 100, "%"))
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
