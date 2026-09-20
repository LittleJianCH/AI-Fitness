package com.aifitness

import android.app.LocaleConfig
import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.aifitness.contract.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@SdkSuppress(minSdkVersion = 33)
class LocalizationTests {
    @get:Rule val compose = createComposeRule()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun localized(tags: String) =
        context.createConfigurationContext(
            Configuration(context.resources.configuration).apply {
                setLocales(LocaleList.forLanguageTags(tags))
            }
        )

    @Test
    fun packagedResourcesFallbackAliasesAndPlurals() {
        assertEquals(
            setOf("en", "zh-Hans"),
            LocaleConfig(context).supportedLocales!!.toLanguageTags().split(",").toSet(),
        )
        for (tag in listOf("en", "en-GB", "fr-FR", "zh-Hant")) {
            assertEquals(tag, "Sign in", localized(tag).getString(R.string.login))
        }
        for (tag in listOf("zh-Hans", "zh-CN", "zh-SG", "fr-FR,zh-Hans")) {
            assertEquals(tag, "登录", localized(tag).getString(R.string.login))
        }
        assertEquals(
            "Power, 1 sample. Use the buttons below to select raw points.",
            localized("en").resources.getQuantityString(R.plurals.chart_samples, 1, "Power", 1),
        )
        assertEquals(
            "Power, 2 samples. Use the buttons below to select raw points.",
            localized("en").resources.getQuantityString(R.plurals.chart_samples, 2, "Power", 2),
        )
        assertEquals(
            "功率，2 个样本；使用下方按钮选择原始点。",
            localized("zh-Hans").resources.getQuantityString(R.plurals.chart_samples, 2, "功率", 2),
        )
    }

    @Test
    fun realWorkoutUserContentStaysVerbatimAcrossConfigurationChanges() {
        val endpoint = requireNotNull(InstrumentationRegistry.getArguments().getString("server"))
        require(endpoint.startsWith("http://127.0.0.1:"))
        val api = FitnessApi(endpoint)
        val workout = runBlocking {
            val session = api.login("android_fixture_user", "synthetic android fixture password")
            try {
                api.workout(session.token, api.workouts(session.token).items.first().id)
            } finally {
                api.logout(session.token)
            }
        }
        val original = workout.toJson().toString()
        val displayed =
            workout.copy(
                workoutUserData =
                    workout.workoutUserData.copy(
                        workoutTitle = "settings",
                        workoutNotes = "Mixed <b>骑行</b> notes",
                    )
            )
        var locale by mutableStateOf("en")
        compose.setContent {
            val local = localized(locale)
            CompositionLocalProvider(
                LocalContext provides local,
                LocalConfiguration provides local.resources.configuration,
            ) {
                val model = remember {
                    FitnessViewModel(
                        object : CredentialVault {
                            override fun read(): SavedSession? = null

                            override fun save(session: SavedSession) {}

                            override fun clear() {}
                        },
                        true,
                    )
                }
                MaterialTheme {
                    WorkoutDetailScreen(
                        FitnessState(
                            detail =
                                Detail(
                                    displayed,
                                    analysisLoading = false,
                                    analysisError = ClientIssue.Unknown,
                                )
                        ),
                        model,
                    )
                }
            }
        }
        for ((tag, label) in listOf("en" to "Route", "zh-Hans" to "路线")) {
            compose.runOnIdle { locale = tag }
            compose.onNodeWithTag("workoutDetail").performScrollToIndex(0)
            compose.onNodeWithText("settings").assertExists()
            compose.onNodeWithText(label).assertExists()
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(hasText("Mixed <b>骑行</b> notes"))
            compose.onNodeWithText("Mixed <b>骑行</b> notes").assertExists()
            compose
                .onNodeWithTag("workoutDetail")
                .performScrollToNode(
                    hasText(
                        if (tag == "en") "The operation failed. Try again later."
                        else "操作未完成，请稍后重试。"
                    )
                )
        }
        assertEquals(original, workout.toJson().toString())
    }
}
