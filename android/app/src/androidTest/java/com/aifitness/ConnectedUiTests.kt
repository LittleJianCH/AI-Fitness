package com.aifitness

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Required server argument comes only from the disposable-cluster harness. Never mocks HTTP. */
@SdkSuppress(minSdkVersion = 33)
class ConnectedUiTests {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun loginRestoreBrowseSettingsHistoryAndLogout() {
        val endpoint = InstrumentationRegistry.getArguments().getString("server")
        require(endpoint != null && endpoint.startsWith("http://127.0.0.1:")) {
            "Run scripts/android_integration_test --device on a disposable emulator"
        }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val locale = InstrumentationRegistry.getArguments().getString("locale") ?: "en"
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            context.getSystemService(android.app.LocaleManager::class.java).applicationLocales =
                android.os.LocaleList.forLanguageTags(locale)
        }
        SessionVault(context).clear()
        var activity = ActivityScenario.launch(MainActivity::class.java)
        try {
            waitForTag("login")
            compose
                .onNodeWithTag("login")
                .assertTextEquals(if (locale == "zh-Hans") "登录" else "Sign in")
            screenshot("login")
            compose.onNodeWithTag("server").performTextReplacement(endpoint)
            compose.onNodeWithTag("username").performTextInput("android_fixture_user")
            assertPasswordInput(activity, "password")
            compose.onNodeWithTag("password").performTextInput("synthetic android fixture password")
            compose.onNodeWithTag("login").performClick()
            waitForTag("workoutList")
            waitIdle()
            val saved = SessionVault(context).read()
            assertNotNull(saved)
            assertEquals(endpoint, saved!!.endpoint)
            assertFalse(
                context.getSharedPreferences("session", 0).all.toString().contains(saved.token)
            )
            // Closing the Activity destroys its ViewModel; reopening validates the saved token
            // through /me.
            activity.close()
            activity = ActivityScenario.launch(MainActivity::class.java)
            waitForTag("workoutList")
            waitIdle()
            compose.onNodeWithTag("workoutList").performScrollToNode(hasTestTag("loadMore"))
            compose.onNodeWithTag("loadMore").performClick()
            waitIdle()
            compose.onNodeWithTag("loadMore").assertDoesNotExist()
            openWorkout("Android synthetic cycling 00")
            screenshot("workout")
            waitForTag("workoutDetail")
            waitIdle()
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(hasTestTag("metric-powerMetric"))
            compose.onNodeWithTag("metric-powerMetric").performClick()
            waitForTag("selectedPoint")
            waitForTag("metricScreen")
            screenshot("metric")
            compose.onNodeWithText(text(R.string.back)).performClick()
            waitIdle()
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(hasText(text(R.string.view_history)))
            compose.onNodeWithText(text(R.string.view_history)).performClick()
            waitForTag("trainingHistory")
            compose.onNodeWithText(text(R.string.back)).performClick()
            waitForTag("workoutDetail")
            waitIdle()
            compose.onNodeWithText(text(R.string.workout), useUnmergedTree = true).performClick()
            openWorkout("Android synthetic running 01")
            for ((metric, expected) in
                listOf(
                    "stepLengthMetric" to "1.10 m",
                    "verticalOscillationMetric" to "0.080 m",
                    "groundContactTimeMetric" to "0.250 s",
                )) {
                compose
                    .onNodeWithTag("workoutDetail")
                    .performScrollToNode(hasTestTag("metric-$metric"))
                compose.onNodeWithTag("metric-$metric").performClick()
                waitForTag("selectedPoint")
                compose
                    .onAllNodesWithTag("selectedPoint")[0]
                    .assertTextContains(expected, substring = true)
                compose
                    .onNodeWithText(text(R.string.distance), useUnmergedTree = true)
                    .performClick()
                compose
                    .onAllNodesWithTag("selectedPoint")[0]
                    .assertTextContains(expected, substring = true)
                compose.onNodeWithText(text(R.string.back)).performClick()
                waitForTag("workoutDetail")
                waitIdle()
            }
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(hasText(text(R.string.running_dynamics)))
            compose.onNodeWithText(text(R.string.running_dynamics)).assertExists()
            compose.onNodeWithText(text(R.string.settings), useUnmergedTree = true).performClick()
            screenshot("settings")
            compose.onNodeWithText(text(R.string.body_settings)).performClick()
            waitIdle()
            compose.onNodeWithText(text(R.string.update_body)).performClick()
            compose.onNodeWithTag("effective_time").performTextReplacement("2020-01-01T00:00:00Z")
            compose.onNodeWithTag("body_mass").performTextInput("70")
            compose.onNodeWithTag("bodySettings").performScrollToNode(hasTestTag("saveBody"))
            compose.onNodeWithTag("saveBody").performClick()
            waitIdle()
            val persistedBody = runBlocking {
                FitnessApi(endpoint).settings(saved.token)
            }
            assertEquals(70.0, persistedBody.settingsBodyProfiles.single().bodyMassKilograms!!, 0.0)
            compose.onNodeWithText(text(R.string.back)).performClick()
            waitIdle()
            compose.onNodeWithText(text(R.string.equipment)).performClick()
            waitIdle()
            compose.onNodeWithText(text(R.string.add_equipment)).performClick()
            compose.onNodeWithTag("equipment_name").performTextInput("Synthetic UI bicycle")
            compose.onNodeWithTag("saveEquipment").performScrollTo().performClick()
            waitIdle()
            compose.onNodeWithText("Synthetic UI bicycle").assertExists()
            compose
                .onNodeWithText(text(R.string.training_history), useUnmergedTree = true)
                .performClick()
            compose.onNodeWithTag("history_end").performTextReplacement("2026-09-10")
            compose.onNodeWithTag("history_days").performTextReplacement("2")
            compose.onNodeWithTag("historyComplete").performScrollTo().performClick()
            compose.onNodeWithTag("historyNoPrior").performScrollTo().performClick()
            compose.onNodeWithTag("loadHistory").performScrollTo().performClick()
            waitIdle()
            compose
                .onNodeWithTag("trainingHistory")
                .performScrollToNode(hasText(text(R.string.training_trend)))
            compose.onNodeWithText(text(R.string.training_trend)).assertExists()
            compose.onNodeWithText(text(R.string.settings), useUnmergedTree = true).performClick()
            compose.onNodeWithText(text(R.string.account_sessions)).performClick()
            waitForTag("logout")
            waitIdle()
            assertPasswordInput(activity, "currentPassword")
            assertPasswordInput(activity, "newPassword")
            compose.onNodeWithTag("currentPassword").performTextInput("Synthetic-wrong-password")
            compose.onNodeWithTag("newPassword").performTextInput("Synthetic-replacement-password")
            compose
                .onNode(hasScrollToIndexAction())
                .performScrollToNode(hasText(text(R.string.change_password_logout)))
            compose.onNodeWithText(text(R.string.change_password_logout)).performClick()
            waitIdle()
            compose
                .onNodeWithTag("statusMessage")
                .assertTextEquals(text(R.string.issue_current_password))
            assertEquals(saved, SessionVault(context).read())
            assertEquals(
                "android_fixture_user",
                runBlocking { FitnessApi(endpoint).me(saved.token).username },
            )
            compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag("logout"))
            compose.onNodeWithTag("logout").performClick()
            waitForTag("login")
            assertNull(SessionVault(context).read())
        } finally {
            activity.close()
        }
    }

    private fun screenshot(screen: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val locale = InstrumentationRegistry.getArguments().getString("locale") ?: "en"
        instrumentation.waitForIdleSync()
        Thread.sleep(300) // Allow the rendered frame to reach the system screenshot surface.
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        val file = java.io.File(instrumentation.targetContext.filesDir, "i18n-$locale-$screen.png")
        file.outputStream().use {
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }

    private fun assertPasswordInput(activity: ActivityScenario<MainActivity>, tag: String) {
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performClick()
        compose.waitForIdle()
        activity.onActivity { screen ->
            val info = android.view.inputmethod.EditorInfo()
            val connection = screen.currentFocus?.onCreateInputConnection(info)
            assertNotNull("Password field must expose an IME connection", connection)
            assertEquals(
                android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD,
                info.inputType and android.text.InputType.TYPE_MASK_VARIATION,
            )
            assertEquals(0, info.inputType and android.text.InputType.TYPE_TEXT_FLAG_AUTO_CORRECT)
        }
    }

    private fun text(id: Int) =
        InstrumentationRegistry.getInstrumentation().targetContext.getString(id)

    private fun waitForTag(tag: String) =
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }

    private fun openWorkout(title: String) {
        waitForTag("workoutList")
        waitIdle()
        compose.onNodeWithTag("workoutList").performScrollToNode(hasText(title))
        compose.onNodeWithText(title).performClick()
        waitForTag("workoutDetail")
        waitIdle()
    }

    private fun waitIdle() =
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag("busy").fetchSemanticsNodes().isEmpty()
        }
}
