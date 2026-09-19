package com.aifitness

import com.aifitness.contract.CalendarDay
import java.time.LocalDate
import java.time.ZoneId

/** Calendar presentation only. The server owns HRSS/CTL/ATL and unknown/rest semantics. */
fun trainingCalendar(
    ending: LocalDate,
    count: Int,
    zone: ZoneId,
    complete: Boolean,
): List<CalendarDay> {
    require(count in 1..366)
    return (0 until count).map { offset ->
        val date = ending.minusDays((count - offset - 1).toLong())
        CalendarDay(
            calendarDate = date.toString(),
            calendarStart = date.atStartOfDay(zone).toInstant().toString(),
            calendarEnd = date.plusDays(1).atStartOfDay(zone).toInstant().toString(),
            calendarRecordingComplete = complete,
        )
    }
}
