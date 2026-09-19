package com.aifitness

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class TransportTests {
    @Test
    fun bearerNeverFollowsRedirectAndRawProblemIsNotPresented() = runBlocking {
        val redirectedRequests = AtomicInteger(0)
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/api/v1/me") { exchange ->
            assertEquals(
                "Bearer synthetic-token",
                exchange.requestHeaders.getFirst("Authorization"),
            )
            assertNull(exchange.requestHeaders.getFirst("Cookie"))
            exchange.responseHeaders.add("Location", "/leak")
            exchange.sendResponseHeaders(302, -1)
            exchange.close()
        }
        server.createContext("/leak") { exchange ->
            redirectedRequests.incrementAndGet()
            exchange.sendResponseHeaders(500, -1)
            exchange.close()
        }
        server.start()
        try {
            val api = FitnessApi("http://127.0.0.1:${server.address.port}")
            try {
                api.me("synthetic-token")
                fail("Redirect accepted")
            } catch (error: ApiFailure) {
                assertEquals(302, error.status)
                assertFalse(userMessage(error).contains("synthetic-token"))
            }
            assertEquals(0, redirectedRequests.get())
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun cancellationDisconnectsBlockingRequest() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/api/v1/me") { exchange ->
            entered.countDown()
            release.await(5, TimeUnit.SECONDS)
            exchange.close()
        }
        server.start()
        try {
            val api = FitnessApi("http://127.0.0.1:${server.address.port}")
            val request = launch { api.me("synthetic-token") }
            assertTrue(withContext(Dispatchers.IO) { entered.await(2, TimeUnit.SECONDS) })
            withTimeout(2_000) { request.cancelAndJoin() }
            assertTrue(request.isCancelled)
        } finally {
            release.countDown()
            server.stop(0)
        }
    }
}
