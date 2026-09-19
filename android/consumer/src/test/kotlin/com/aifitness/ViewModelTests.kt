package com.aifitness

import androidx.lifecycle.ViewModelStore
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class, DelicateCoroutinesApi::class)
class ViewModelTests {
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
