"use strict";

const { clean, fingerprint } = require("./bm-contracts");

const MEMORY_KEYS = new Set([
  "main_apps",
  "weak_hours",
  "bedtime_minute",
  "breakfast_end_minute",
  "lunch_end_minute",
  "pattern_cluster",
  "last_plan_outcome",
  "last_intent",
  "last_topic",
  "last_bm_topic",
  "last_bai_topic",
]);

const SCALAR_KEYS = [
  "channel",
  "assistant_channel",
  "language",
  "locale",
  "trigger",
  "mode",
  "web_preview",
  "has_selected_apps",
  "screen_time_authorized",
  "is_blank_active",
  "emergency_unlocks_remaining",
  "vacation_mode_active",
  "weekly_break_count",
  "weekly_protected_minutes",
  "recommended_duration_minutes",
  "risk_window",
  "recommendation_id",
  "autonomy_consent",
  "device_execution_ready",
  "mode_name",
  "signal_type",
  "threshold_minutes",
  "risk_hour",
  "weak_hour",
  "risk_score",
  "relapse_risk_score",
  "sleep_minutes",
  "sleep_delta_minutes",
  "sleep_deficit_minutes",
  "social_use_delta_percent",
  "app_use_delta_percent",
  "screen_time_delta_percent",
  "break_count_today",
  "relapse_count_today",
  "unlock_count_today",
  "category",
  "dominant_category",
  "health_signal_reasons",
];

const ARRAY_KEYS = ["authorized_action_types", "available_modes"];

function normalizeStringArray(value, maxItems = 8, maxLength = 80) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => typeof item === "string" ? item : item && typeof item === "object" ? item.name : "")
    .map((item) => clean(item, maxLength))
    .filter(Boolean)
    .slice(0, maxItems);
}

function normalizeAutonomyGrant(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const grant = {
    active: value.active === true,
    action_types: normalizeStringArray(value.action_types, 16, 64),
  };
  const source = clean(value.source, 80);
  const expiresAt = clean(value.expires_at, 64);
  if (source) grant.source = source;
  if (expiresAt) grant.expires_at = expiresAt;
  return grant;
}

function normalizeMemory(memory = {}) {
  if (!memory || typeof memory !== "object" || Array.isArray(memory)) return {};
  return Object.keys(memory).reduce((result, key) => {
    if (!MEMORY_KEYS.has(key)) return result;
    const value = memory[key];
    if (Array.isArray(value)) result[key] = value.slice(0, 8).map((item) => clean(item, 80)).filter(Boolean);
    else if (typeof value === "number" && Number.isFinite(value)) result[key] = Math.round(value);
    else if (typeof value === "boolean") result[key] = value;
    else if (typeof value === "string") result[key] = clean(value, 120);
    return result;
  }, {});
}

function normalizeConversation(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(-8).map((message) => ({
    role: clean(message?.role, 24) || "user",
    content: clean(message?.content || message?.text, 420),
  })).filter((message) => message.content);
}

function normalizeObject(value, maxKeys = 24) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.keys(value).slice(0, maxKeys).reduce((result, key) => {
    const item = value[key];
    if (typeof item === "number" && Number.isFinite(item)) result[key] = item;
    else if (typeof item === "boolean") result[key] = item;
    else if (typeof item === "string") result[key] = clean(item, 120);
    return result;
  }, {});
}

function buildAgentContext(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const result = {};
  for (const key of SCALAR_KEYS) {
    if (source[key] !== undefined) result[key] = source[key];
  }
  for (const key of ARRAY_KEYS) {
    if (source[key] !== undefined) result[key] = normalizeStringArray(source[key]);
  }
  if (source.autonomy_grant !== undefined) {
    const grant = normalizeAutonomyGrant(source.autonomy_grant);
    if (grant) result.autonomy_grant = grant;
  }
  result.memory = normalizeMemory(source.memory);
  result.recent_messages = normalizeConversation(source.recent_messages || source.conversation);
  result.metrics = normalizeObject(source.metrics);
  result.signals = normalizeObject(source.signals);
  result.context_fingerprint = fingerprint({
    ...result,
    recent_messages: result.recent_messages.map((message) => ({ role: message.role, length: message.content.length })),
  });
  return result;
}

module.exports = {
  MEMORY_KEYS,
  buildAgentContext,
  normalizeConversation,
  normalizeMemory,
};
