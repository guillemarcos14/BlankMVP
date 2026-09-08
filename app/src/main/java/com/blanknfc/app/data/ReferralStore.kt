package com.blanknfc.app.data

import android.content.Context
import android.util.Log
import com.blanknfc.app.BuildConfig
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

data class ReferralState(
    val referralCount: Int = 0,
    val requiredReferrals: Int = 3,
    val rewardDays: Int = 7,
    val rewardUnlocked: Boolean = false,
    val rewardEndsAt: String? = null
)

class ReferralStore(
    private val context: Context,
    private val backendClient: BlankBackendClient,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val prefs = context.getSharedPreferences("blanked_referrals", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(loadState())
    val state: StateFlow<ReferralState> = _state.asStateFlow()

    val hasReferralProAccess: Boolean
        get() = prefs.getString(REWARD_ENDS_AT_KEY, null)?.let { value ->
            runCatching { Instant.parse(value).isAfter(Instant.now()) }.getOrDefault(false)
        } ?: false

    fun refreshStatus() {
        scope.launch {
            runCatching {
                val response = backendClient.post(
                    "referrals",
                    JSONObject().apply {
                        put("action", "status")
                        put("anonymous_user_id", backendClient.anonymousUserId)
                    }
                )
                applyResponse(response)
            }.onFailure {
                Log.w("BlankedReferrals", "Referral status failed", it)
            }
        }
    }

    fun activate(referrerAnonymousUserId: String) {
        scope.launch {
            runCatching {
                val response = backendClient.post(
                    "referrals",
                    JSONObject().apply {
                        put("action", "activate")
                        put("referrer_anonymous_user_id", referrerAnonymousUserId.trim())
                        put("referred_anonymous_user_id", backendClient.anonymousUserId)
                        put("source", "android")
                        put("app_version", BuildConfig.VERSION_NAME)
                        put("build_number", BuildConfig.VERSION_CODE.toString())
                    }
                )
                applyResponse(response)
            }.onFailure {
                Log.w("BlankedReferrals", "Referral activation failed", it)
            }
        }
    }

    private fun applyResponse(response: JSONObject) {
        val state = ReferralState(
            referralCount = response.optInt("referral_count", 0),
            requiredReferrals = response.optInt("required_referrals", 3),
            rewardDays = response.optInt("reward_days", 7),
            rewardUnlocked = response.optBoolean("reward_unlocked", false),
            rewardEndsAt = response.takeIf { it.has("reward_ends_at") }?.optString("reward_ends_at")
        )
        _state.value = state
        prefs.edit()
            .putInt(REFERRAL_COUNT_KEY, state.referralCount)
            .putString(REWARD_ENDS_AT_KEY, state.rewardEndsAt)
            .apply()
    }

    private fun loadState(): ReferralState {
        return ReferralState(
            referralCount = prefs.getInt(REFERRAL_COUNT_KEY, 0),
            rewardEndsAt = prefs.getString(REWARD_ENDS_AT_KEY, null)
        )
    }

    companion object {
        private const val REFERRAL_COUNT_KEY = "referral_count"
        private const val REWARD_ENDS_AT_KEY = "reward_ends_at"
    }
}
