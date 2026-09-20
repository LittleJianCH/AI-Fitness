package com.aifitness

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.aifitness.contract.Appearance

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val model: FitnessViewModel = viewModel {
                FitnessViewModel(SessionVault(application), BuildConfig.DEBUG)
            }
            FitnessApp(model)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FitnessApp(model: FitnessViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val dark =
        when (state.settings?.settingsSoftware?.softwareAppearance) {
            Appearance.darkAppearance -> true
            Appearance.lightAppearance -> false
            else -> isSystemInDarkTheme()
        }
    MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
        BackHandler(
            state.user != null && state.screen !in listOf(Screen.Workouts, Screen.Settings)
        ) {
            model.back()
        }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(screenTitle(state.screen)) },
                    navigationIcon = {
                        if (
                            state.user != null &&
                                state.screen !in listOf(Screen.Workouts, Screen.Settings)
                        ) {
                            TextButton(onClick = model::back) {
                                Text(stringResource(R.string.back))
                            }
                        }
                    },
                )
            },
            bottomBar = {
                if (state.user != null)
                    NavigationBar {
                        NavigationBarItem(
                            selected = state.screen == Screen.Workouts,
                            onClick = { model.navigate(Screen.Workouts) },
                            icon = { Text("◎") },
                            label = { Text(stringResource(R.string.workout)) },
                        )
                        NavigationBarItem(
                            selected = state.screen == Screen.History,
                            onClick = { model.navigate(Screen.History) },
                            icon = { Text("▥") },
                            label = { Text(stringResource(R.string.training_history)) },
                        )
                        NavigationBarItem(
                            selected =
                                state.screen in
                                    listOf(
                                        Screen.Settings,
                                        Screen.Software,
                                        Screen.Body,
                                        Screen.Equipment,
                                        Screen.Account,
                                    ),
                            onClick = { model.navigate(Screen.Settings) },
                            icon = { Text("⚙") },
                            label = { Text(stringResource(R.string.settings)) },
                        )
                    }
            },
        ) { insets ->
            Column(Modifier.fillMaxSize().padding(insets)) {
                if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth().testTag("busy"))
                state.message?.let {
                    Text(
                        it.text(),
                        Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                            .testTag("statusMessage"),
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                when {
                    state.restoring ->
                        Box(Modifier.padding(24.dp)) {
                            Text(stringResource(R.string.restoring_session))
                        }
                    state.user == null -> LoginScreen(state, model)
                    else ->
                        when (val screen = state.screen) {
                            Screen.Workouts -> WorkoutListScreen(state, model)
                            is Screen.Detail -> WorkoutDetailScreen(state, model)
                            is Screen.Metric -> MetricScreen(state.detail, screen.kind)
                            Screen.History -> HistoryScreen(state, model)
                            Screen.Settings -> SettingsScreen(state, model)
                            Screen.Software -> SoftwareScreen(state, model)
                            Screen.Body -> BodyScreen(state, model)
                            Screen.Equipment -> EquipmentScreen(state, model)
                            Screen.Account -> AccountScreen(state, model)
                        }
                }
            }
        }
    }
}

@Composable
private fun screenTitle(screen: Screen): String =
    when (screen) {
        Screen.Workouts -> stringResource(R.string.workouts)
        Screen.Settings -> stringResource(R.string.settings)
        Screen.Software -> stringResource(R.string.software_settings)
        Screen.Body -> stringResource(R.string.body_settings)
        Screen.Equipment -> stringResource(R.string.equipment)
        Screen.Account -> stringResource(R.string.account_sessions)
        Screen.History -> stringResource(R.string.training_history)
        is Screen.Detail -> stringResource(R.string.workout_detail)
        is Screen.Metric -> screen.kind.title()
    }

@Composable
private fun LoginScreen(state: FitnessState, model: FitnessViewModel) {
    var endpoint by remember(state.endpoint) { mutableStateOf(state.endpoint) }
    var username by remember { mutableStateOf("") }
    // Passwords are never saveable state and never placed in bundles.
    var password by remember { mutableStateOf("") }
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineLarge)
        }
        item { Text(stringResource(R.string.login_intro)) }
        item {
            OutlinedTextField(
                endpoint,
                { endpoint = it },
                label = { Text(stringResource(R.string.server_https)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("server"),
            )
        }
        item {
            OutlinedTextField(
                username,
                { username = it },
                label = { Text(stringResource(R.string.username)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("username"),
            )
        }
        item {
            OutlinedTextField(
                password,
                { password = it },
                label = { Text(stringResource(R.string.password)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions =
                    KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        autoCorrectEnabled = false,
                    ),
                modifier = Modifier.fillMaxWidth().testTag("password"),
            )
        }
        item {
            Button(
                onClick = {
                    model.login(endpoint, username, password)
                    password = ""
                },
                enabled =
                    !state.busy &&
                        endpoint.isNotBlank() &&
                        username.isNotBlank() &&
                        password.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().testTag("login"),
            ) {
                Text(stringResource(R.string.login))
            }
        }
        if (state.endpoint.isNotEmpty())
            item {
                TextButton(onClick = model::restore, enabled = !state.busy) {
                    Text(stringResource(R.string.retry_restore))
                }
            }
    }
}

@Composable
private fun WorkoutListScreen(state: FitnessState, model: FitnessViewModel) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.testTag("workoutList"),
    ) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    stringResource(R.string.your_workouts),
                    style = MaterialTheme.typography.headlineSmall,
                )
                TextButton(onClick = { model.refreshWorkouts() }, enabled = !state.busy) {
                    Text(stringResource(R.string.refresh))
                }
            }
        }
        if (state.workouts.isEmpty() && !state.busy)
            item { Text(stringResource(R.string.empty_workouts)) }
        items(state.workouts, key = { it.id }) { workout ->
            Card(
                onClick = { model.navigate(Screen.Detail(workout.id)) },
                modifier = Modifier.fillMaxWidth().testTag("workout-${workout.id}"),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        workout.userData.workoutTitle ?: stringResource(R.string.workout),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    Text(dateTime(workout.range.rangeStart))
                    Text(
                        "${number(workout.recorded.summaryDistance?.div(1000), "km")} · ${number(workout.recorded.summaryTimerTime, "s")}"
                    )
                }
            }
        }
        state.cursor?.let {
            item {
                Button(
                    onClick = { model.refreshWorkouts(true) },
                    enabled = !state.busy,
                    modifier = Modifier.testTag("loadMore"),
                ) {
                    Text(stringResource(R.string.load_more))
                }
            }
        }
    }
}

@Composable
fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            content()
        }
    }
}

@Composable
fun ValueRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, Modifier.weight(1f))
    }
}
