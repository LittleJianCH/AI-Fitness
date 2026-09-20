package com.aifitness

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.aifitness.contract.parseInstant
import kotlin.math.abs
import kotlin.math.cos

@Composable
fun PointChart(
    points: List<ChartPoint>,
    title: String,
    xUnit: String,
    yUnit: String,
    gap: Double? = null,
    scatter: Boolean = false,
    bars: Boolean = false,
    logarithmicX: Boolean = false,
    xDigits: Int = 1,
    yDigits: Int = 1,
    // Opt in at known timestamp boundaries. Other labels, including user text, stay verbatim.
    selectedLabel: (@Composable (Int) -> String)? = null,
) {
    if (points.isEmpty()) {
        Text(stringResource(R.string.empty_chart, title))
        return
    }
    var selected by remember(points) { mutableIntStateOf(0) }
    val visible =
        remember(points, gap, bars) { if (bars) points else renderingPoints(points, gap = gap) }
    val xMin = remember(points, bars) { points.minOf { if (bars) it.barRange().start else it.x } }
    val xMax =
        remember(points, bars) { points.maxOf { if (bars) it.barRange().endInclusive else it.x } }
    val yMin = remember(points, bars) { if (bars) 0.0 else points.minOf { it.y } }
    val yMax = remember(points) { points.maxOf { it.y } }
    val scaledMin = chartX(xMin, logarithmicX)
    val scaledMax = chartX(xMax, logarithmicX)
    val xRange = (scaledMax - scaledMin).takeIf { it > 0 } ?: 1.0
    val yRange = (yMax - yMin).takeIf { it > 0 } ?: 1.0
    val color = MaterialTheme.colorScheme.primary
    Text(title, style = MaterialTheme.typography.titleMedium)
    Text(
        "${number(yMin, yUnit, yDigits)} — ${number(yMax, yUnit, yDigits)}",
        style = MaterialTheme.typography.bodySmall,
    )
    val description = pluralStringResource(R.plurals.chart_samples, points.size, title, points.size)
    Canvas(
        Modifier.fillMaxWidth()
            .height(180.dp)
            .testTag("chart")
            .semantics { contentDescription = description }
            .pointerInput(points, scatter, bars, logarithmicX) {
                detectTapGestures { location ->
                    val target = scaledMin + (location.x / size.width).coerceIn(0f, 1f) * xRange
                    selected =
                        if (bars) nearestBarIndex(points, target)
                        else if (scatter)
                            points.indices.minBy { i ->
                                val p = points[i]
                                val dx =
                                    ((chartX(p.x, logarithmicX) - scaledMin) / xRange * size.width -
                                        location.x)
                                val dy = ((1 - (p.y - yMin) / yRange) * size.height - location.y)
                                dx * dx + dy * dy
                            }
                        else
                            points.indices.minBy {
                                abs(chartX(points[it].x, logarithmicX) - target)
                            }
                }
            }
    ) {
        fun position(point: ChartPoint) =
            Offset(
                ((chartX(point.x, logarithmicX) - scaledMin) / xRange * size.width).toFloat(),
                ((1 - (point.y - yMin) / yRange) * size.height).toFloat(),
            )
        drawLine(
            Color.Gray.copy(alpha = .3f),
            Offset(0f, size.height),
            Offset(size.width, size.height),
        )
        visible.forEachIndexed { index, point ->
            val at = position(point)
            if (bars) {
                val range = point.barRange()
                val left = ((range.start - xMin) / xRange * size.width).toFloat()
                val right = ((range.endInclusive - xMin) / xRange * size.width).toFloat()
                // Adjacent histogram bins share boundaries; category bars have a visual gap.
                val inset = if (point.upperX == null) (right - left) * .175f else 0f
                drawRect(
                    color,
                    Offset(left + inset, at.y),
                    Size(right - left - 2 * inset, size.height - at.y),
                )
            } else if (scatter || isolatedChartPoint(visible, index)) drawCircle(color, 3f, at)
            else if (index > 0 && !point.breakBefore)
                drawLine(color, position(visible[index - 1]), at, strokeWidth = 3f)
        }
        val current = points[selected.coerceIn(points.indices)]
        val selectedAt =
            if (bars) {
                val range = current.barRange()
                position(current.copy(x = (range.start + range.endInclusive) / 2))
            } else position(current)
        drawCircle(color, 6f, selectedAt)
    }
    val categories = bars && points.all { it.upperX == null }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            number(if (categories) points.minOf { it.x } else xMin, xUnit, xDigits),
            style = MaterialTheme.typography.bodySmall,
        )
        Text(
            number(if (categories) points.maxOf { it.x } else xMax, xUnit, xDigits),
            style = MaterialTheme.typography.bodySmall,
        )
    }
    val current = points[selected.coerceIn(points.indices)]
    Text(
        "${number(current.x, xUnit, xDigits)} · ${number(current.y, yUnit, yDigits)}",
        modifier = Modifier.testTag("selectedPoint"),
    )
    Text(
        selectedLabel?.invoke(selected.coerceIn(points.indices)) ?: current.label,
        modifier = Modifier.testTag("selectedPointLabel"),
        style = MaterialTheme.typography.bodySmall,
    )
    Row {
        TextButton(onClick = { selected-- }, enabled = selected > 0) {
            Text(stringResource(R.string.previous_point))
        }
        TextButton(onClick = { selected++ }, enabled = selected < points.lastIndex) {
            Text(stringResource(R.string.next_point))
        }
    }
}

@Composable
fun RouteCard(workout: com.aifitness.contract.Workout, gap: Double) {
    var fullScreen by remember { mutableStateOf(false) }
    val positions = workout.motion.motionPosition
    SectionCard(stringResource(R.string.route)) {
        if (positions.isEmpty()) Text(stringResource(R.string.empty_route))
        else {
            RouteCanvas(workout, gap, Modifier.height(240.dp))
            Text(stringResource(R.string.route_hint))
            TextButton(onClick = { fullScreen = true }) {
                Text(stringResource(R.string.fullscreen_route))
            }
        }
    }
    if (fullScreen)
        Dialog(
            onDismissRequest = { fullScreen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(Modifier.fillMaxSize()) {
                Column(Modifier.padding(20.dp)) {
                    TextButton(onClick = { fullScreen = false }) {
                        Text(stringResource(R.string.close_route))
                    }
                    Text(
                        stringResource(R.string.route_gestures),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    RouteCanvas(workout, gap, Modifier.weight(1f))
                }
            }
        }
}

@Composable
private fun RouteCanvas(workout: com.aifitness.contract.Workout, gap: Double, modifier: Modifier) {
    val rawRoute =
        remember(workout, gap) {
            val source = workout.motion.motionPosition
            val latitude = source.firstOrNull()?.value?.latitude ?: 0.0
            val points = source.mapIndexed { index, sample ->
                val breaks =
                    index > 0 &&
                        java.time.Duration.between(
                                parseInstant(source[index - 1].timestamp),
                                parseInstant(sample.timestamp),
                            )
                            .toMillis() / 1000.0 > gap
                ChartPoint(
                    sample.value.longitude * cos(Math.toRadians(latitude)),
                    sample.value.latitude,
                    sample.timestamp,
                    breaks,
                )
            }
            points
        }
    val route = remember(rawRoute) { renderingPoints(rawRoute) }
    if (route.isEmpty()) return
    var selected by remember(rawRoute) { mutableIntStateOf(0) }
    var zoom by remember(workout.workoutId) { mutableFloatStateOf(1f) }
    var pan by remember(workout.workoutId) { mutableStateOf(Offset.Zero) }
    val minX = rawRoute.minOf { it.x }
    val maxX = rawRoute.maxOf { it.x }
    val minY = rawRoute.minOf { it.y }
    val maxY = rawRoute.maxOf { it.y }
    val color = MaterialTheme.colorScheme.primary
    val description = pluralStringResource(R.plurals.route_positions, rawRoute.size, rawRoute.size)
    Canvas(
        modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = description
            }
            .pointerInput(workout.workoutId) {
                detectTransformGestures { _, move, scale, _ ->
                    zoom = (zoom * scale).coerceIn(1f, 12f)
                    pan += move
                }
            }
            .pointerInput(rawRoute, zoom, pan) {
                detectTapGestures { tap ->
                    val range = maxOf(maxX - minX, maxY - minY, .00001)
                    val scale = minOf(size.width, size.height) * .85 / range
                    selected =
                        rawRoute.indices.minBy { index ->
                            val point = rawRoute[index]
                            val dx =
                                size.width / 2 +
                                    (point.x - (minX + maxX) / 2) * scale * zoom +
                                    pan.x - tap.x
                            val dy =
                                size.height / 2 - (point.y - (minY + maxY) / 2) * scale * zoom +
                                    pan.y - tap.y
                            dx * dx + dy * dy
                        }
                }
            }
    ) {
        val range = maxOf(maxX - minX, maxY - minY, .00001)
        val scale = minOf(size.width, size.height) * .85 / range
        fun at(p: ChartPoint) =
            Offset(
                (size.width / 2 + (p.x - (minX + maxX) / 2) * scale * zoom).toFloat(),
                (size.height / 2 - (p.y - (minY + maxY) / 2) * scale * zoom).toFloat(),
            ) + pan
        route.forEachIndexed { index, point ->
            if (index > 0 && !point.breakBefore)
                drawLine(color, at(route[index - 1]), at(point), 4f)
        }
        drawCircle(Color(0xFF238636), 7f, at(route.first()))
        drawCircle(Color(0xFFDA3633), 7f, at(route.last()), style = Stroke(4f))
        drawCircle(color, 10f, at(rawRoute[selected]), style = Stroke(3f))
    }
    val position = workout.motion.motionPosition[selected]
    Text(
        "${dateTime(position.timestamp)} · ${number(position.value.latitude, digits = 5)}, ${number(position.value.longitude, digits = 5)}",
        style = MaterialTheme.typography.bodySmall,
    )
    Row {
        TextButton(onClick = { selected-- }, enabled = selected > 0) {
            Text(stringResource(R.string.previous_position))
        }
        TextButton(onClick = { selected++ }, enabled = selected < rawRoute.lastIndex) {
            Text(stringResource(R.string.next_position))
        }
    }
    TextButton(
        onClick = {
            zoom = 1f
            pan = Offset.Zero
        }
    ) {
        Text(stringResource(R.string.reset_route))
    }
}
