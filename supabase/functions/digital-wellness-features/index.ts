import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function cleanText(value: unknown, maxLength = 240) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanBoolean(value: unknown) {
  if (value === true) return true;
  if (value === false) return false;
  return null;
}

function requireSafePrivacy(payload: Record<string, any>) {
  const privacy = payload?.privacy || {};
  const blocked = [
    privacy.raw_health_samples_sent,
    privacy.raw_sleep_stage_timestamps_sent,
    privacy.exact_app_selection_sent,
    privacy.exact_location_sent,
  ].some((value) => value === true);

  if (blocked) {
    throw new Error("raw_or_sensitive_payload_rejected");
  }
}

function compactPayload(payload: Record<string, any>) {
  return {
    schema_version: cleanNumber(payload.schema_version),
    generated_at: payload.generated_at,
    period_start: payload.period_start,
    period_end: payload.period_end,
    profile: payload.profile || {},
    daily: Array.isArray(payload.daily) ? payload.daily.slice(-14) : [],
    weekly: payload.weekly || {},
    correlations: payload.correlations || {},
    privacy: payload.privacy || {},
  };
}

function hourWindow(hour: unknown) {
  const start = Number(hour);
  if (!Number.isFinite(start)) return null;
  const end = (start + 2) % 24;
  return `${String(start).padStart(2, "0")}:00-${String(end).padStart(2, "0")}:00`;
}

function buildInsight(payload: Record<string, any>) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const profile = payload.profile || {};
  const patterns: string[] = [];
  const recommendations: string[] = [];

  if ((weekly.blocked_minutes || 0) > 0) {
    patterns.push(`${weekly.blocked_minutes} protected minutes across ${weekly.blocks_completed || 0} completed blocks.`);
  } else {
    patterns.push("Not enough completed blocks yet; start with one protected window this week.");
  }

  if (weekly.avg_sleep_minutes) {
    patterns.push(`Average sleep signal is ${Math.round((weekly.avg_sleep_minutes / 60) * 10) / 10}h.`);
  }

  if (weekly.avg_steps) {
    patterns.push(`Average activity signal is ${weekly.avg_steps} steps.`);
  }

  const weakWindow = weekly.worst_focus_window || hourWindow(weekly.weakest_hour);
  if (weakWindow) {
    recommendations.push(`Protect ${weakWindow} before opening high-friction apps.`);
  }

  if ((weekly.plan_adherence_percent || 0) < 60) {
    recommendations.push("Lower the next block length and repeat the same window for cleaner learning.");
  } else {
    recommendations.push("Keep the current plan stable for one more week.");
  }

  if (correlations.relapses_after_short_sleep > 0 || correlations.screen_risk_after_bad_sleep === "high") {
    recommendations.push("Use a lighter block after short sleep instead of relying on willpower.");
  }

  if ((weekly.selection_count || 0) < 3) {
    recommendations.push("Add at least three distracting apps or categories to improve protection.");
  }

  const nextStep = recommendations[0] || "Complete one focus block so Blanked can learn your baseline.";
  const confidence = Math.min(100, Math.max(20, (weekly.days_count || 0) * 6 + (weekly.active_days_7d || 0) * 8));

  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    confidence,
    motivation_cluster: profile.motivation_cluster || "general_control",
    summary: `Your current plan difficulty is ${weekly.recommended_plan_difficulty || "baseline"} with ${weekly.plan_adherence_percent || 0}% adherence.`,
    patterns: patterns.slice(0, 3),
    recommendations: recommendations.slice(0, 3),
    next_step: nextStep,
    risk_window: weakWindow || null,
  };
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("supabase_env_not_configured");
    }

    const body = await request.json();
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }

    const payload = compactPayload(body.payload || {});
    requireSafePrivacy(payload);
    const insight = buildInsight(payload);
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data, error } = await supabase
      .from("digital_wellness_feature_payloads")
      .insert({
        anonymous_user_id: anonymousUserId,
        schema_version: payload.schema_version || 1,
        period_start: payload.period_start,
        period_end: payload.period_end,
        payload,
        insight,
        platform: "ios",
        locale: cleanText(body.locale, 40),
        app_version: cleanText(body.app_version, 40),
        build_number: cleanText(body.build_number, 40),
        data_consent: true,
        consent_text: cleanText(body.consent_text, 240),
        privacy_raw_health_samples_sent: cleanBoolean(payload.privacy.raw_health_samples_sent),
        privacy_raw_sleep_stage_timestamps_sent: cleanBoolean(payload.privacy.raw_sleep_stage_timestamps_sent),
        privacy_exact_app_selection_sent: cleanBoolean(payload.privacy.exact_app_selection_sent),
        privacy_exact_location_sent: cleanBoolean(payload.privacy.exact_location_sent),
        submitted_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (error) {
      throw error;
    }

    return json(200, { ok: true, id: data?.id || null, insight });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message === "raw_or_sensitive_payload_rejected" ? 400 : 500;
    return json(status, { error: "digital_wellness_features_failed", detail: message });
  }
});
