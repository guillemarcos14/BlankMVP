package com.blanknfc.app.data

import android.content.Context
import com.blanknfc.app.BuildConfig
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID
import org.json.JSONObject

class BlankBackendClient(private val context: Context) {
    private val prefs = context.getSharedPreferences("blanked_backend", Context.MODE_PRIVATE)
    private val baseUrl = BuildConfig.BLANK_API_BASE_URL.trimEnd('/') + "/"

    val anonymousUserId: String
        get() {
            val existing = prefs.getString(USER_ID_KEY, null)
            if (!existing.isNullOrBlank()) return existing
            val created = UUID.randomUUID().toString()
            prefs.edit().putString(USER_ID_KEY, created).apply()
            return created
        }

    fun commonEnvelope(extra: JSONObject = JSONObject()): JSONObject {
        return JSONObject().apply {
            put("anonymous_user_id", anonymousUserId)
            put("locale", Locale.getDefault().toLanguageTag())
            put("platform", "android")
            put("app_version", BuildConfig.VERSION_NAME)
            put("build_number", BuildConfig.VERSION_CODE.toString())
            put("data_consent", true)
            put("consent_text", "Product analytics")
            extra.keys().forEach { key -> put(key, extra.get(key)) }
        }
    }

    fun post(endpoint: String, body: JSONObject): JSONObject {
        val connection = (URL(baseUrl + endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 12000
            readTimeout = 12000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
        }
        OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
            writer.write(body.toString())
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val responseText = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        connection.disconnect()
        if (status !in 200..299) {
            throw IllegalStateException("Backend $endpoint failed with $status: ${responseText.take(240)}")
        }
        return if (responseText.isBlank()) JSONObject() else JSONObject(responseText)
    }

    companion object {
        private const val USER_ID_KEY = "blanked_anonymous_user_id"
    }
}
