package com.aifitness

import com.aifitness.contract.*
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Same Kotlin transport and generated decoder used by the APK, with a real disposable API. */
class ConnectedApiTests {
    @Test
    fun realBackendLoginPaginationAnalysisSettingsHistoryAndRevocation() = runBlocking {
        val endpoint = System.getenv("AI_FITNESS_ANDROID_TEST_SERVER")
        assumeTrue(
            "Run scripts/android_integration_test --host for real backend coverage",
            endpoint != null,
        )
        require(endpoint!!.startsWith("http://127.0.0.1:"))
        val api = FitnessApi(FitnessApi.validateEndpoint(endpoint, true))
        val session = api.login("android_fixture_user", "synthetic android fixture password")
        val token = session.token
        try {
            assertEquals(session.user.id, api.me(token).id)
            val first = api.workouts(token)
            assertEquals(20, first.items.size)
            assertNotNull(first.nextCursor)
            val second = api.workouts(token, first.nextCursor)
            assertEquals(3, second.items.size)
            assertNull(second.nextCursor)
            assertEquals(23, (first.items + second.items).map { it.id }.toSet().size)
            val settings = api.settings(token)
            val heart =
                HeartRateProfile(
                    heartRateResting = 50.0,
                    heartRateThreshold = 160.0,
                    heartRateMaximum = 190.0,
                    heartRateWeighting = LoadWeighting.exponent192,
                )
            val sport = SportProfile(sportThresholdWatts = 250.0, sportHeartRate = heart)
            val profile =
                BodyProfile(
                    bodyProfileId = UUID.randomUUID().toString(),
                    bodyEffectiveFrom = "2020-01-01T00:00:00Z",
                    bodyMassKilograms = 70.0,
                    bodyHeightMetres = 1.75,
                    bodyCycling = sport,
                    bodyRunning = sport,
                )
            val equipment =
                Equipment(
                    equipmentId = UUID.randomUUID().toString(),
                    equipmentKind = EquipmentKind.bicycle,
                    equipmentName = "Synthetic test bicycle",
                    equipmentMassKilograms = 8.0,
                    equipmentRetired = false,
                )
            val saved =
                api.saveSettings(
                    token,
                    settings.copy(
                        settingsBodyProfiles = settings.settingsBodyProfiles + profile,
                        settingsEquipment = settings.settingsEquipment + equipment,
                        settingsSoftware = SoftwareSettings(Appearance.darkAppearance),
                    ),
                )
            assertNotEquals(settings.settingsRevision, saved.settingsRevision)
            assertEquals(saved, api.settings(token))
            try {
                api.saveSettings(token, settings)
                fail("Stale settings accepted")
            } catch (error: ApiFailure) {
                assertEquals(409, error.status)
            }
            val retired =
                api.saveSettings(
                    token,
                    saved.copy(
                        settingsEquipment =
                            listOf(
                                equipment.copy(
                                    equipmentName = "Renamed synthetic bicycle",
                                    equipmentRetired = true,
                                )
                            )
                    ),
                )
            assertTrue(retired.settingsEquipment.single().equipmentRetired)
            for (card in (first.items + second.items).distinctBy { it.summary::class }) {
                val workout = api.workout(token, card.id)
                val analysis = api.analysis(token, card.id)
                assertEquals(workout.workoutRevision, analysis.analysisRevision)
                assertEquals(retired.settingsRevision, analysis.analysisSettingsRevision)
                assertTrue(workout.motion.motionPosition.isNotEmpty())
                assertTrue(analysis.analysisMetrics.any { it.metricKind == MetricKind.gradeMetric })
                assertTrue(
                    analysis.analysisMetrics.any { it.metricKind == MetricKind.temperatureMetric }
                )
                assertTrue(analysis.analysisPowerZones.isNotEmpty())
                assertTrue(analysis.analysisHeart.heartZones.isNotEmpty())
                assertTrue(analysis.analysisSplits.isNotEmpty())
                assertTrue(analysis.analysisRelationships.isNotEmpty())
                if (workout.running) assertNotNull(analysis.analysisRunning)
                val curve = api.powerCurve(token, card.id)
                assertEquals(workout.workoutRevision, curve.inputRevision)
                assertTrue(curve.points.any { it.best != null })
            }
            val unknown =
                api.history(
                    token,
                    TrainingHistoryRequest(
                        historyCalendar =
                            trainingCalendar(
                                LocalDate.parse("2026-09-07"),
                                3,
                                ZoneId.of("Asia/Shanghai"),
                                false,
                            ),
                        historyAssumeNoPriorLoad = true,
                    ),
                )
            assertEquals(3, unknown.trainingDays.size)
            assertNull(unknown.trainingDays.last().trainingTotalLoad)
            val rest =
                api.history(
                    token,
                    TrainingHistoryRequest(
                        historyCalendar =
                            trainingCalendar(
                                LocalDate.parse("2026-09-10"),
                                2,
                                ZoneId.of("Asia/Shanghai"),
                                true,
                            ),
                        historyAssumeNoPriorLoad = true,
                    ),
                )
            assertEquals(0.0, rest.trainingDays.first().trainingTotalLoad!!, 0.0)
            assertEquals(0.0, rest.trainingDays.last().trainingFitness!!, 0.0)
            assertTrue(api.sessions(token).items.any { it.current })
        } finally {
            api.logout(token)
        }
        try {
            api.me(token)
            fail("Revoked token accepted")
        } catch (error: ApiFailure) {
            assertEquals(401, error.status)
        }
    }
}
