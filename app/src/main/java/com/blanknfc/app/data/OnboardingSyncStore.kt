package com.blanknfc.app.data

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject

data class AndroidOnboardingResponses(
    val name: String,
    val ageRange: String,
    val goal: String,
    val profile: String,
    val dailyHours: Double,
    val aiGoal: String,
    val weakMoment: String,
    val selectedPlan: String
)

class OnboardingSyncStore(
    private val backendClient: BlankBackendClient,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    fun trackStepViewed(step: String) {
        trackFunnelEvent("onboarding_step_viewed", step, emptyMap())
    }

    fun submit(responses: AndroidOnboardingResponses) {
        scope.launch {
            runCatching {
                backendClient.post(
                    "onboarding-responses",
                    backendClient.commonEnvelope(
                        JSONObject().apply {
                            put("name", responses.name)
                            put("age_range", responses.ageRange)
                            put("goal", responses.goal)
                            put("profile", responses.profile)
                            put("daily_hours", responses.dailyHours)
                            put("ai_goal", responses.aiGoal)
                            put("weak_moment", responses.weakMoment)
                            put("selected_plan", responses.selectedPlan)
                            put("consent_text", "Personalize my plan")
                        }
                    )
                )
                backendClient.post(
                    "funnel-event",
                    backendClient.commonEnvelope(
                        JSONObject().apply {
                            put("event", "onboarding_personalization_submitted")
                            put("step", "personalization")
                            put(
                                "properties",
                                JSONObject().apply {
                                    put("age_range", responses.ageRange)
                                    put("goal", responses.goal)
                                    put("profile", responses.profile)
                                    put("daily_hours", responses.dailyHours)
                                    put("selected_plan", responses.selectedPlan)
                                }
                            )
                        }
                    )
                )
            }.onFailure {
                Log.w("BlankedOnboarding", "Onboarding sync failed", it)
            }
        }
    }

    private fun trackFunnelEvent(event: String, step: String, properties: Map<String, String>) {
        scope.launch {
            runCatching {
                backendClient.post(
                    "funnel-event",
                    backendClient.commonEnvelope(
                        JSONObject().apply {
                            put("event", event)
                            put("step", step)
                            put("properties", JSONObject(properties))
                        }
                    )
                )
            }.onFailure {
                Log.w("BlankedOnboarding", "Funnel sync failed", it)
            }
        }
    }
}
