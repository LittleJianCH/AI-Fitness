package com.aifitness

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Required server argument comes only from the disposable-cluster harness. Never mocks HTTP. */
class ConnectedUiTests {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun loginRestoreBrowseSettingsHistoryAndLogout() {
        val endpoint = InstrumentationRegistry.getArguments().getString("server")
        require(endpoint != null && endpoint.startsWith("http://127.0.0.1:")) {
            "Run scripts/android_integration_test --device on a disposable emulator"
        }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        SessionVault(context).clear()
        var activity = ActivityScenario.launch(MainActivity::class.java)
        try {
            waitForTag("login")
            compose.onNodeWithTag("server").performTextReplacement(endpoint)
            compose.onNodeWithTag("username").performTextInput("android_fixture_user")
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
            compose.onNodeWithTag("workoutList").performScrollToIndex(1)
            compose.onAllNodes(hasTestTagPrefix("workout-"))[0].performClick()
            waitForTag("workoutDetail")
            waitIdle()
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(hasTestTag("metric-powerMetric"))
            compose.onNodeWithTag("metric-powerMetric").performClick()
            waitForTag("selectedPoint")
            compose.onNodeWithText("返回").performClick()
            waitIdle()
            compose.onNodeWithTag("workoutDetail").performScrollToNode(hasText("查看训练历史"))
            compose.onNodeWithText("查看训练历史").performClick()
            waitForTag("trainingHistory")
            compose.onNodeWithText("返回").performClick()
            waitForTag("workoutDetail")
            waitIdle()
            compose.onNodeWithText("设置", useUnmergedTree = true).performClick()
            compose.onNodeWithText("个人身体参数").performClick()
            waitIdle()
            compose.onNodeWithText("更新个人参数").performClick()
            compose
                .onNodeWithTag("生效时间 (UTC ISO 8601)")
                .performTextReplacement("2020-01-01T00:00:00Z")
            compose.onNodeWithTag("体重 (kg)").performTextInput("70")
            compose.onNodeWithTag("bodySettings").performScrollToNode(hasTestTag("saveBody"))
            compose.onNodeWithTag("saveBody").performClick()
            waitIdle()
            compose.onNodeWithText("返回").performClick()
            waitIdle()
            compose.onNodeWithText("器材").performClick()
            waitIdle()
            compose.onNodeWithText("添加器材").performClick()
            compose.onNodeWithTag("器材名称").performTextInput("Synthetic UI bicycle")
            compose.onNodeWithTag("saveEquipment").performScrollTo().performClick()
            waitIdle()
            compose.onNodeWithText("Synthetic UI bicycle").assertExists()
            compose.onNodeWithText("训练历史", useUnmergedTree = true).performClick()
            compose.onNodeWithTag("结束日期 (YYYY-MM-DD)").performTextReplacement("2026-09-10")
            compose.onNodeWithTag("天数 (1–366)").performTextReplacement("2")
            compose.onNodeWithTag("historyComplete").performScrollTo().performClick()
            compose.onNodeWithTag("historyNoPrior").performScrollTo().performClick()
            compose.onNodeWithTag("loadHistory").performScrollTo().performClick()
            waitIdle()
            compose.onNodeWithTag("trainingHistory").performScrollToNode(hasText("训练趋势 · 后端计算"))
            compose.onNodeWithText("训练趋势 · 后端计算").assertExists()
            compose.onNodeWithText("设置", useUnmergedTree = true).performClick()
            compose.onNodeWithText("账号与登录会话").performClick()
            waitForTag("logout")
            waitIdle()
            compose.onNodeWithTag("logout").performClick()
            waitForTag("login")
            assertNull(SessionVault(context).read())
        } finally {
            activity.close()
        }
    }

    private fun waitForTag(tag: String) =
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }

    private fun waitIdle() =
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag("busy").fetchSemanticsNodes().isEmpty()
        }
}

private fun hasTestTagPrefix(prefix: String): SemanticsMatcher =
    SemanticsMatcher("test tag begins with $prefix") {
        it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true
    }
