package com.aifitness

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import com.aifitness.contract.MetricKind

@Composable
fun number(value: Double?, unit: String = "", digits: Int = 1): String =
    formatNumber(value, unit, digits, LocalConfiguration.current.locales[0])
        ?: stringResource(R.string.not_recorded)

@Composable
fun MetricKind.title(): String =
    when (this) {
        MetricKind.heartRateMetric -> stringResource(R.string.heart_rate)
        MetricKind.powerMetric -> stringResource(R.string.power)
        MetricKind.speedMetric -> stringResource(R.string.speed)
        MetricKind.cadenceMetric -> stringResource(R.string.cadence)
        MetricKind.altitudeMetric -> stringResource(R.string.altitude)
        MetricKind.stepLengthMetric -> stringResource(R.string.step_length)
        MetricKind.verticalOscillationMetric -> stringResource(R.string.vertical_oscillation)
        MetricKind.groundContactTimeMetric -> stringResource(R.string.ground_contact_time)
        MetricKind.temperatureMetric -> stringResource(R.string.temperature)
        MetricKind.gradeMetric -> stringResource(R.string.grade)
    }

@Composable
fun MetricKind.format(value: Double?, running: Boolean): String =
    number(value, unit(running), digits())

@Composable
fun pace(speed: Double?): String {
    if (speed == null || speed <= 0) return stringResource(R.string.not_recorded)
    val seconds = (1000 / speed).toInt()
    return String.format(
        LocalConfiguration.current.locales[0],
        "%d:%02d /km",
        seconds / 60,
        seconds % 60,
    )
}

@Composable
fun ClientIssue.text(): String =
    stringResource(
        when (this) {
            ClientIssue.ResponseTooLarge -> R.string.issue_response_large
            ClientIssue.StaleWorkout -> R.string.issue_stale
            ClientIssue.SessionPagination -> R.string.issue_pagination
            ClientIssue.AnalysisTooLarge -> R.string.issue_analysis_large
            ClientIssue.AnalysisUnavailable -> R.string.issue_analysis_unavailable
            ClientIssue.Authentication -> R.string.issue_auth
            ClientIssue.Forbidden -> R.string.issue_forbidden
            ClientIssue.Missing -> R.string.issue_missing
            ClientIssue.Conflict -> R.string.issue_conflict
            ClientIssue.Validation -> R.string.issue_validation
            ClientIssue.RateLimit -> R.string.issue_rate_limit
            ClientIssue.Network -> R.string.issue_network
            ClientIssue.Unknown -> R.string.issue_unknown
            ClientIssue.SavedSessionLocked -> R.string.issue_unlock
            ClientIssue.Saved -> R.string.saved
        }
    )

@Composable
fun dateTime(value: String): String =
    formatDateTime(value, LocalConfiguration.current.locales[0], java.time.ZoneId.systemDefault())
