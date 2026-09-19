package com.aifitness

import com.aifitness.contract.*
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject

class StaleWorkoutAnalysis : Exception("Workout revision changed")

class ApiFailure(val status: Int, val code: String?) : Exception("API request failed ($status)")

/** Native requests never follow redirects or share a browser cookie store. */
class FitnessApi(val endpoint: String) {
    suspend fun login(username: String, password: String): NativeSession =
        request(
            "POST",
            "/auth/native/login",
            null,
            JSONObject()
                .put("username", username)
                .put("password", password)
                .put("deviceName", "AI Fitness Android"),
            NativeSession::fromJson,
        )

    suspend fun me(token: String): User = request("GET", "/me", token, decode = User::fromJson)

    suspend fun logout(token: String) = request("POST", "/auth/logout", token) { Unit }

    suspend fun workouts(token: String, cursor: String? = null): Page_WorkoutCard =
        request(
            "GET",
            "/workouts?limit=20" + (cursor?.let { "&cursor=${encode(it)}" } ?: ""),
            token,
            decode = Page_WorkoutCard::fromJson,
        )

    suspend fun workout(token: String, id: String): Workout =
        request("GET", "/workouts/${encode(id)}", token, decode = Workout::fromJson)

    suspend fun analysis(token: String, id: String): WorkoutAnalysis =
        request(
            "GET",
            "/workouts/${encode(id)}/analysis",
            token,
            decode = WorkoutAnalysis::fromJson,
        )

    suspend fun powerCurve(token: String, id: String): PowerCurve =
        request("GET", "/workouts/${encode(id)}/power-curve", token, decode = PowerCurve::fromJson)

    suspend fun settings(token: String): UserSettings =
        request("GET", "/settings", token, decode = UserSettings::fromJson)

    suspend fun saveSettings(token: String, settings: UserSettings): UserSettings =
        request("PUT", "/settings", token, settings.toJson(), UserSettings::fromJson)

    suspend fun history(token: String, request: TrainingHistoryRequest): TrainingHistory =
        request(
            "POST",
            "/analysis/training-history",
            token,
            request.toJson(),
            TrainingHistory::fromJson,
        )

    suspend fun sessions(token: String, cursor: String? = null): Page_Session =
        request(
            "GET",
            "/auth/sessions?limit=100" + (cursor?.let { "&cursor=${encode(it)}" } ?: ""),
            token,
            decode = Page_Session::fromJson,
        )

    suspend fun revoke(token: String, id: String) =
        request("DELETE", "/auth/sessions/${encode(id)}", token) { Unit }

    suspend fun revokeAll(token: String) = request("DELETE", "/auth/sessions", token) { Unit }

    suspend fun changePassword(token: String, current: String, new: String) =
        request(
            "PUT",
            "/auth/password",
            token,
            JSONObject().put("currentPassword", current).put("newPassword", new),
        ) {
            Unit
        }

    private suspend fun <T> request(
        method: String,
        path: String,
        token: String?,
        body: JSONObject? = null,
        decode: (JSONObject) -> T,
    ): T =
        withContext(Dispatchers.IO) {
            suspendCancellableCoroutine { continuation ->
                val connection =
                    URI(endpoint + "/api/v1" + path).toURL().openConnection() as HttpURLConnection
                continuation.invokeOnCancellation { connection.disconnect() }
                try {
                    connection.instanceFollowRedirects = false
                    connection.useCaches = false
                    connection.connectTimeout = 15_000
                    connection.readTimeout = 30_000
                    connection.requestMethod = method
                    connection.setRequestProperty("Accept", "application/json")
                    token?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
                    body?.let {
                        connection.doOutput = true
                        connection.setRequestProperty("Content-Type", "application/json")
                        connection.outputStream.use { output ->
                            output.write(it.toString().toByteArray(Charsets.UTF_8))
                        }
                    }
                    val status = connection.responseCode
                    if (status !in 200..299) {
                        val problem =
                            connection.errorStream?.bufferedReader()?.use {
                                it.readTextBounded(65_536)
                            }
                        val code =
                            try {
                                problem?.let { JSONObject(it).optString("code") }
                            } catch (_: Exception) {
                                null
                            }
                        throw ApiFailure(status, code)
                    }
                    val json =
                        if (status == 204) JSONObject()
                        else
                            connection.inputStream.bufferedReader().use {
                                JSONObject(it.readTextBounded(64 * 1024 * 1024))
                            }
                    if (continuation.isActive) continuation.resume(decode(json))
                } catch (error: Exception) {
                    if (continuation.isActive) continuation.resumeWithException(error)
                } finally {
                    connection.disconnect()
                }
            }
        }

    companion object {
        fun validateEndpoint(input: String, debug: Boolean): String {
            val url = URI(input.trim())
            require(
                url.host != null &&
                    url.rawUserInfo == null &&
                    url.rawQuery == null &&
                    url.rawFragment == null
            )
            require(url.path in listOf("", "/", "/api/v1", "/api/v1/"))
            val loopback =
                url.host.lowercase() in setOf("localhost", "127.0.0.1", "10.0.2.2", "[::1]", "::1")
            require(url.scheme == "https" || (debug && url.scheme == "http" && loopback))
            require(url.port == -1 || url.port in 1..65535)
            return URI(url.scheme, null, url.host, url.port, null, null, null).toASCIIString()
        }

        private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
    }
}

private fun java.io.Reader.readTextBounded(max: Int): String {
    val result = StringBuilder()
    val buffer = CharArray(8192)
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        require(result.length + count <= max) { "Response exceeds client limit" }
        result.append(buffer, 0, count)
    }
    return result.toString()
}

fun userMessage(error: Exception): String {
    if (error is StaleWorkoutAnalysis) return "运动已修改，请刷新运动详情以读取同一版本。"
    when ((error as? ApiFailure)?.code) {
        "analysis_too_large" -> return "这段历史的数据量超过处理上限，请缩短日期范围后重试。"
        "analysis_unavailable" -> return "当前历史数据暂时无法完成分析，请检查记录与个人参数。"
    }
    return when ((error as? ApiFailure)?.status) {
        401 -> "登录已失效或账号密码不正确，请重新登录。"
        403 -> "当前操作未获允许。"
        404 -> "记录不存在或已删除。"
        409 -> "设置已在其他设备修改。请重新加载，再应用你的修改。"
        422 -> "服务器未接受这些参数。请检查数值、心率顺序和生效日期。"
        429 -> "请求过于频繁，请稍后重试。"
        else -> "请求未完成，请检查连接后重试。"
    }
}
