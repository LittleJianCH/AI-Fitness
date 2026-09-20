package com.aifitness

import androidx.lifecycle.ViewModelStore
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class, DelicateCoroutinesApi::class)
class ViewModelTests {
    @Test
    fun passwordChangeRechecksSessionBeforeClearingCredentials() = runBlocking {
        val main = newSingleThreadContext("password-session-test")
        Dispatchers.setMain(main)
        val fixtures = File(System.getProperty("fixtureDir"))
        val expired = AtomicBoolean(false)
        val meCalls = AtomicInteger(0)
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/api/v1/me") { exchange ->
            meCalls.incrementAndGet()
            val bytes =
                if (expired.get()) {
                    """{"code":"unauthenticated"}""".toByteArray()
                } else {
                    """{"id":"00000000-0000-0000-0000-000000000001","username":"synthetic","createdAt":"2026-09-01T00:00:00Z"}"""
                        .toByteArray()
                }
            exchange.sendResponseHeaders(if (expired.get()) 401 else 200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        for ((path, filename) in
            listOf("workouts" to "list-response.json", "settings" to "settings-response.json")) {
            server.createContext("/api/v1/$path") { exchange ->
                val bytes = File(fixtures, filename).readBytes()
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
        }
        server.createContext("/api/v1/auth/password") { exchange ->
            val bytes = """{"code":"unauthenticated"}""".toByteArray()
            exchange.sendResponseHeaders(401, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        val credential = SavedSession("http://127.0.0.1:${server.address.port}", "synthetic-token")
        val vault = MemoryVault(credential)
        val store = ViewModelStore()
        try {
            val model =
                withContext(main) { FitnessViewModel(vault, true).also { store.put("test", it) } }
            waitFor { !model.state.value.busy }
            withContext(main) {
                model.changePassword("wrong-current", "Synthetic-replacement-password")
            }
            waitFor { !model.state.value.busy }
            assertNotNull(
                "An incorrect current password must not sign out a valid session",
                model.state.value.user,
            )
            assertEquals(credential, vault.read())
            assertEquals(ClientIssue.IncorrectCurrentPassword, model.state.value.message)
            assertEquals(2, meCalls.get())
            expired.set(true)
            withContext(main) {
                model.changePassword("wrong-current", "Synthetic-replacement-password")
            }
            waitFor { !model.state.value.busy }
            assertNull(model.state.value.user)
            assertNull(vault.read())
            assertEquals(ClientIssue.Authentication, model.state.value.message)
            assertEquals(3, meCalls.get())
        } finally {
            withContext(main) { store.clear() }
            server.stop(0)
            Dispatchers.resetMain()
            main.close()
        }
    }

    @Test
    fun metricNavigationKeepsPendingAnalysisAndPowerCurve() = runBlocking {
        val main = newSingleThreadContext("metric-navigation-test")
        Dispatchers.setMain(main)
        val fixtures = File(System.getProperty("fixtureDir"))
        val id =
            JSONObject(File(fixtures, "workout-response.json").readText()).getString("workoutId")
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger(0)
        val pool = Executors.newCachedThreadPool()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.executor = pool
        fun fixture(path: String, filename: String) {
            server.createContext(path) { exchange ->
                val bytes = File(fixtures, filename).readBytes()
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
        }
        server.createContext("/api/v1/me") { exchange ->
            val bytes =
                """{"id":"00000000-0000-0000-0000-000000000001","username":"synthetic","createdAt":"2026-09-01T00:00:00Z"}"""
                    .toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        fixture("/api/v1/workouts", "list-response.json")
        fixture("/api/v1/settings", "settings-response.json")
        fixture("/api/v1/workouts/$id", "workout-response.json")
        fixture("/api/v1/workouts/$id/power-curve", "power-curve-response.json")
        server.createContext("/api/v1/workouts/$id/analysis") { exchange ->
            calls.incrementAndGet()
            entered.countDown()
            release.await(10, TimeUnit.SECONDS)
            val bytes = File(fixtures, "analysis-response.json").readBytes()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        val store = ViewModelStore()
        try {
            val vault =
                MemoryVault(
                    SavedSession("http://127.0.0.1:${server.address.port}", "synthetic-token")
                )
            val model =
                withContext(main) { FitnessViewModel(vault, true).also { store.put("test", it) } }
            waitFor { !model.state.value.busy }
            withContext(main) { model.navigate(Screen.Detail(id)) }
            assertTrue(withContext(Dispatchers.IO) { entered.await(5, TimeUnit.SECONDS) })
            val kind = model.state.value.detail!!.workout.metricKinds().first()
            withContext(main) { model.navigate(Screen.Metric(kind)) }
            assertTrue(model.state.value.busy)
            assertTrue(model.state.value.detail!!.analysisLoading)
            release.countDown()
            waitFor { !model.state.value.busy }
            assertEquals(Screen.Metric(kind), model.state.value.screen)
            assertNotNull(model.state.value.detail!!.analysis)
            assertNotNull(model.state.value.detail!!.curve)
            assertFalse(model.state.value.detail!!.analysisLoading)
            assertFalse(model.state.value.detail!!.curveLoading)
            assertEquals(1, calls.get())
        } finally {
            release.countDown()
            withContext(main) { store.clear() }
            server.stop(0)
            pool.shutdownNow()
            Dispatchers.resetMain()
            main.close()
        }
    }

    /** Fault responses wrap real backend-produced payloads; this is a state regression, not E2E. */
    @Test
    fun analysisFailureRetainsWorkoutAndHistoryReturnsToDetail() = runBlocking {
        val main = newSingleThreadContext("viewmodel-test-main")
        Dispatchers.setMain(main)
        val fixtures = File(System.getProperty("fixtureDir"))
        val workout = JSONObject(File(fixtures, "workout-response.json").readText())
        val id = workout.getString("workoutId")
        val analysisCalls = AtomicInteger(0)
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        fun respond(path: String, filename: String) {
            server.createContext(path) { exchange ->
                val bytes = File(fixtures, filename).readBytes()
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
        }
        server.createContext("/api/v1/me") { exchange ->
            val bytes =
                """{"id":"00000000-0000-0000-0000-000000000001","username":"synthetic","createdAt":"2026-09-01T00:00:00Z"}"""
                    .toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        respond("/api/v1/workouts", "list-response.json")
        respond("/api/v1/settings", "settings-response.json")
        respond("/api/v1/workouts/$id", "workout-response.json")
        respond("/api/v1/workouts/$id/power-curve", "power-curve-response.json")
        server.createContext("/api/v1/workouts/$id/analysis") { exchange ->
            if (analysisCalls.incrementAndGet() == 1) {
                exchange.sendResponseHeaders(503, -1)
                exchange.close()
            } else {
                val bytes = File(fixtures, "analysis-response.json").readBytes()
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
        }
        server.start()
        val vault =
            MemoryVault(SavedSession("http://127.0.0.1:${server.address.port}", "synthetic-token"))
        val store = ViewModelStore()
        try {
            val model =
                withContext(main) { FitnessViewModel(vault, true).also { store.put("test", it) } }
            waitFor { !model.state.value.busy }
            withContext(main) { model.navigate(Screen.Detail(id)) }
            waitFor { !model.state.value.busy }
            assertEquals(id, model.state.value.detail?.workout?.workoutId)
            assertNotNull(model.state.value.detail?.analysisError)
            assertNotNull(model.state.value.detail?.curve)
            withContext(main) { model.retryAnalysis() }
            waitFor { !model.state.value.busy }
            assertNotNull(model.state.value.detail?.analysis)
            withContext(main) {
                model.navigate(Screen.History)
                model.back()
            }
            assertEquals(Screen.Detail(id), model.state.value.screen)
        } finally {
            withContext(main) { store.clear() }
            server.stop(0)
            Dispatchers.resetMain()
            main.close()
        }
    }

    private suspend fun waitFor(check: () -> Boolean) =
        withTimeout(10_000) {
            while (!check()) delay(20)
        }
}

class MemoryVault(private var saved: SavedSession? = null) : CredentialVault {
    override fun read(): SavedSession? = saved

    override fun save(session: SavedSession) {
        saved = session
    }

    override fun clear() {
        saved = null
    }
}
