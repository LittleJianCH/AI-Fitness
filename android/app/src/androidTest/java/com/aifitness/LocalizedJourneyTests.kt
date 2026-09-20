package com.aifitness

import android.app.LocaleManager
import android.os.LocaleList
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test

/** Small acceptance journey in the actual installed app and disposable HTTP backend. */
@SdkSuppress(minSdkVersion = 33)
class LocalizedJourneyTests {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun loginWorkoutMetricAndSettings() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val args = InstrumentationRegistry.getArguments()
        val endpoint = requireNotNull(args.getString("server"))
        require(endpoint.startsWith("http://127.0.0.1:"))
        val language = args.getString("locale") ?: "en"
        instrumentation.runOnMainSync {
            context.getSystemService(LocaleManager::class.java).applicationLocales =
                LocaleList.forLanguageTags(language)
        }
        SessionVault(context).clear()
        ActivityScenario.launch(MainActivity::class.java).use {
            waitTag("login")
            compose
                .onNodeWithTag("login")
                .assertTextEquals(if (language == "zh-Hans") "登录" else "Sign in")
            snap(language, "login")
            compose.onNodeWithTag("server").performTextReplacement(endpoint)
            compose.onNodeWithTag("username").performTextInput("android_fixture_user")
            compose.onNodeWithTag("password").performTextInput("synthetic android fixture password")
            compose.onNodeWithTag("login").performClick()
            waitTag("workoutList")
            waitIdle()
            val session = requireNotNull(SessionVault(context).read())
            val card = runBlocking { FitnessApi(endpoint).workouts(session.token).items.first() }
            compose.onNodeWithTag("workout-${card.id}").performClick()
            waitTag("workoutDetail")
            waitIdle()
            snap(language, "workout")
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(hasTestTag("metric-powerMetric"))
            compose.onNodeWithTag("metric-powerMetric").performClick()
            waitTag("metricScreen")
            compose
                .onAllNodesWithText(if (language == "zh-Hans") "功率" else "Power")
                .get(0)
                .assertExists()
            val firstPowerTimestamp = runBlocking {
                FitnessApi(endpoint)
                    .workout(session.token, card.id)
                    .motion
                    .motionPower
                    .first()
                    .timestamp
            }
            compose
                .onAllNodesWithTag("selectedPointLabel")
                .get(0)
                .assertTextEquals(
                    formatDateTime(
                        firstPowerTimestamp,
                        java.util.Locale.forLanguageTag(language),
                        java.time.ZoneId.systemDefault(),
                    )
                )
            snap(language, "metric")
            compose
                .onNodeWithText(
                    if (language == "zh-Hans") "设置" else "Settings",
                    useUnmergedTree = true,
                )
                .performClick()
            waitTag("settings")
            waitIdle()
            compose
                .onNodeWithText(if (language == "zh-Hans") "软件设置" else "Software settings")
                .assertExists()
            snap(language, "settings")
        }
    }

    private fun waitTag(tag: String) =
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }

    private fun waitIdle() =
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag("busy").fetchSemanticsNodes().isEmpty()
        }

    private fun snap(locale: String, screen: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdleSync()
        Thread.sleep(300)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        java.io
            .File(instrumentation.targetContext.filesDir, "i18n-$locale-$screen.png")
            .outputStream()
            .use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
