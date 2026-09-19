package com.aifitness

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifitness.contract.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface Screen {
    data object Workouts : Screen

    data object Settings : Screen

    data class Detail(val id: String) : Screen

    data class Metric(val kind: MetricKind) : Screen

    data object History : Screen

    data object Software : Screen

    data object Body : Screen

    data object Equipment : Screen

    data object Account : Screen
}

data class Detail(
    val workout: Workout,
    val analysis: WorkoutAnalysis? = null,
    val curve: PowerCurve? = null,
    val analysisError: String? = null,
    val curveError: String? = null,
    val analysisLoading: Boolean = true,
    val curveLoading: Boolean = true,
)

data class FitnessState(
    val restoring: Boolean = true,
    val user: User? = null,
    val endpoint: String = "",
    val screen: Screen = Screen.Workouts,
    val busy: Boolean = false,
    val message: String? = null,
    val workouts: List<WorkoutCard> = emptyList(),
    val cursor: String? = null,
    val detail: Detail? = null,
    val settings: UserSettings? = null,
    val history: TrainingHistory? = null,
    val sessions: List<Session> = emptyList(),
)

class FitnessViewModel(private val vault: CredentialVault, private val debug: Boolean) :
    ViewModel() {
    private val mutable = MutableStateFlow(FitnessState())
    val state = mutable.asStateFlow()
    private var saved: SavedSession? = null
    private var operation: Job? = null
    private var generation = 0L
    private var historyReturn: Screen = Screen.Workouts

    init {
        restore()
    }

    private fun runOperation(block: suspend () -> Unit) {
        operation?.cancel()
        val identity = ++generation
        mutable.value = mutable.value.copy(busy = true, message = null)
        operation = viewModelScope.launch {
            try {
                block()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (identity == generation) {
                    if (error is ApiFailure && error.status == 401 && saved != null) clearSession()
                    mutable.value = mutable.value.copy(message = userMessage(error))
                }
            } finally {
                if (identity == generation)
                    mutable.value = mutable.value.copy(busy = false, restoring = false)
            }
        }
    }

    private suspend fun clearSession() {
        withContext(Dispatchers.IO) { vault.clear() }
        saved = null
        mutable.value = FitnessState(restoring = false, endpoint = mutable.value.endpoint)
    }

    fun restore() = runOperation {
        val credential =
            try {
                withContext(Dispatchers.IO) { vault.read() }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                clearSession()
                mutable.value = mutable.value.copy(message = "无法解锁已保存的会话，请重新登录。")
                return@runOperation
            }
        if (credential == null) return@runOperation
        saved = credential
        val api = FitnessApi(FitnessApi.validateEndpoint(credential.endpoint, debug))
        mutable.value = mutable.value.copy(endpoint = credential.endpoint)
        val user = api.me(credential.token)
        mutable.value = mutable.value.copy(user = user, restoring = false)
        loadInitial(api, credential.token)
    }

    fun login(endpoint: String, username: String, password: String) = runOperation {
        val origin = FitnessApi.validateEndpoint(endpoint, debug)
        val api = FitnessApi(origin)
        val result = api.login(username, password)
        val credential = SavedSession(origin, result.token)
        try {
            withContext(Dispatchers.IO) { vault.save(credential) }
        } catch (error: Exception) {
            // Do not claim a restorable login if secure persistence failed.
            if (error is CancellationException) throw error
            try {
                api.logout(result.token)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {}
            throw error
        }
        saved = credential
        mutable.value =
            FitnessState(restoring = false, user = result.user, endpoint = origin, busy = true)
        loadInitial(api, result.token)
    }

    private suspend fun loadInitial(api: FitnessApi, token: String) {
        val page = api.workouts(token)
        mutable.value = mutable.value.copy(workouts = page.items, cursor = page.nextCursor)
        mutable.value = mutable.value.copy(settings = api.settings(token))
    }

    private fun authenticated(block: suspend (FitnessApi, String) -> Unit) {
        val credential = saved ?: return
        runOperation { block(FitnessApi(credential.endpoint), credential.token) }
    }

    fun refreshWorkouts(more: Boolean = false) = authenticated { api, token ->
        val cursor = if (more) mutable.value.cursor ?: return@authenticated else null
        val page = api.workouts(token, cursor)
        val items =
            (if (more) mutable.value.workouts + page.items else page.items).distinctBy { it.id }
        mutable.value = mutable.value.copy(workouts = items, cursor = page.nextCursor)
    }

    fun navigate(screen: Screen) {
        if (screen == Screen.History && mutable.value.screen != Screen.History) {
            historyReturn =
                when (val current = mutable.value.screen) {
                    is Screen.Detail -> current
                    is Screen.Metric ->
                        mutable.value.detail?.workout?.workoutId?.let { Screen.Detail(it) }
                            ?: Screen.Workouts
                    else -> Screen.Workouts
                }
        }
        operation?.cancel()
        generation++
        mutable.value = mutable.value.copy(screen = screen, busy = false, message = null)
        when (screen) {
            is Screen.Detail -> loadDetail(screen.id)
            Screen.Settings,
            Screen.Software,
            Screen.Body,
            Screen.Equipment -> refreshSettings()
            Screen.Account -> loadSessions()
            else -> Unit
        }
    }

    fun back() {
        navigate(
            when (mutable.value.screen) {
                is Screen.Metric ->
                    Screen.Detail(mutable.value.detail?.workout?.workoutId ?: return)
                Screen.Software,
                Screen.Body,
                Screen.Equipment,
                Screen.Account -> Screen.Settings
                Screen.History -> historyReturn
                else -> Screen.Workouts
            }
        )
    }

    fun loadDetail(id: String) {
        if (mutable.value.detail?.workout?.workoutId != id)
            mutable.value = mutable.value.copy(detail = null)
        authenticated { api, token ->
            val workout = api.workout(token, id)
            require(workout.workoutId == id)
            // Recorded data and route remain available even when either analysis request fails.
            mutable.value = mutable.value.copy(detail = Detail(workout))
            coroutineScope {
                launch { fetchAnalysis(api, token, workout) }
                launch { fetchCurve(api, token, workout) }
            }
        }
    }

    private fun updateDetail(workout: Workout, change: (Detail) -> Detail) {
        val current = mutable.value.detail ?: return
        if (
            current.workout.workoutId == workout.workoutId &&
                current.workout.workoutRevision == workout.workoutRevision
        ) {
            mutable.value = mutable.value.copy(detail = change(current))
        }
    }

    private suspend fun fetchAnalysis(api: FitnessApi, token: String, workout: Workout) {
        updateDetail(workout) {
            it.copy(analysis = null, analysisLoading = true, analysisError = null)
        }
        try {
            val result = api.analysis(token, workout.workoutId)
            if (
                result.analysisWorkoutId != workout.workoutId ||
                    result.analysisRevision != workout.workoutRevision
            )
                throw StaleWorkoutAnalysis()
            updateDetail(workout) { it.copy(analysis = result, analysisLoading = false) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            if (error is ApiFailure && error.status == 401) throw error
            updateDetail(workout) {
                it.copy(analysisLoading = false, analysisError = userMessage(error))
            }
        }
    }

    private suspend fun fetchCurve(api: FitnessApi, token: String, workout: Workout) {
        updateDetail(workout) { it.copy(curve = null, curveLoading = true, curveError = null) }
        try {
            val result = api.powerCurve(token, workout.workoutId)
            if (
                result.curveWorkoutId != workout.workoutId ||
                    result.inputRevision != workout.workoutRevision
            )
                throw StaleWorkoutAnalysis()
            updateDetail(workout) { it.copy(curve = result, curveLoading = false) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            if (error is ApiFailure && error.status == 401) throw error
            updateDetail(workout) { it.copy(curveLoading = false, curveError = userMessage(error)) }
        }
    }

    fun retryAnalysis() {
        val workout = mutable.value.detail?.workout ?: return
        authenticated { api, token -> fetchAnalysis(api, token, workout) }
    }

    fun retryCurve() {
        val workout = mutable.value.detail?.workout ?: return
        authenticated { api, token -> fetchCurve(api, token, workout) }
    }

    fun refreshSettings() = authenticated { api, token ->
        mutable.value = mutable.value.copy(settings = api.settings(token))
    }

    fun saveSettings(settings: UserSettings) = authenticated { api, token ->
        val result = api.saveSettings(token, settings)
        // Existing analysis depends on the settings revision; discard it after a settings write.
        mutable.value =
            mutable.value.copy(settings = result, detail = null, history = null, message = "已保存")
    }

    fun loadHistory(request: TrainingHistoryRequest) {
        mutable.value = mutable.value.copy(history = null)
        authenticated { api, token ->
            mutable.value = mutable.value.copy(history = api.history(token, request))
        }
    }

    fun logout() = authenticated { api, token ->
        api.logout(token)
        clearSession()
    }

    fun forgetLocalSession() = runOperation { clearSession() }

    fun loadSessions() = authenticated { api, token ->
        val sessions = mutableListOf<Session>()
        var cursor: String? = null
        do {
            val page = api.sessions(token, cursor)
            sessions.addAll(page.items)
            cursor = page.nextCursor
        } while (cursor != null)
        mutable.value = mutable.value.copy(sessions = sessions.distinctBy { it.id })
    }

    fun revokeSession(session: Session) = authenticated { api, token ->
        api.revoke(token, session.id)
        if (session.current) clearSession()
        else
            mutable.value =
                mutable.value.copy(
                    sessions = mutable.value.sessions.filterNot { it.id == session.id }
                )
    }

    fun revokeAll() = authenticated { api, token ->
        api.revokeAll(token)
        clearSession()
    }

    fun changePassword(current: String, new: String) = authenticated { api, token ->
        api.changePassword(token, current, new)
        clearSession()
    }
}
