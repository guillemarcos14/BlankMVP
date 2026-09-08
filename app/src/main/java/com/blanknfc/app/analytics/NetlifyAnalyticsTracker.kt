package com.blanknfc.app.analytics

import android.util.Log
import com.blanknfc.app.data.BlankBackendClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject

class NetlifyAnalyticsTracker(
    private val backendClient: BlankBackendClient,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) : AnalyticsTracker {
    override fun track(event: BlankEvent) {
        Log.i("BlankAnalytics", "${event.name} ${event.properties}")
        scope.launch {
            runCatching {
                backendClient.post(
                    "funnel-event",
                    backendClient.commonEnvelope(
                        JSONObject().apply {
                            put("event", event.name)
                            put("platform", "android")
                            put("properties", JSONObject(event.properties))
                        }
                    )
                )
            }.onFailure {
                Log.w("BlankAnalytics", "Failed to send ${event.name}", it)
            }
        }
    }
}
