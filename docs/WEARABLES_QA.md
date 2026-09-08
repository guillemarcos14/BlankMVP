# Wearables QA

Last updated: 2026-09-08

Goal: validate Apple HealthKit and Android Health Connect as aggregator layers before adding direct wearable APIs.

Non-negotiables:

- No medical diagnosis copy.
- No raw Health samples in backend payloads.
- Aggregated features only, after consent.
- Empty, stale and partial-permission states must render without crashes.

## iOS HealthKit

Device setup:

- Install the latest TestFlight build on a real iPhone.
- Pair or sync Apple Watch / Apple Health data before testing.
- Confirm Health permission prompt is clear and optional.

Checks:

- Grant all requested Apple Health permissions.
- Reopen Blanked and open Stats.
- Confirm `Health Sources / Wearables` shows one of: `Connected`, `No data`, `Stale`, or `Partial`.
- Confirm visible metrics when available: sleep, steps, workouts, HR, resting HR, HRV, respiratory rate, oxygen saturation, VO2 max, energy and flights.
- Confirm Digital Wellness report changes plan/recovery context when real Health signals exist.
- Confirm low recovery can trigger BAI proactive alert only when signal is useful.
- Revoke some Health permissions in iOS Settings and confirm the app does not crash.
- Disable Health access and confirm the app works normally without wearable data.

Payload checks:

- Submit AI report sync.
- Confirm `digital-wellness-features` stores aggregated fields only.
- Confirm payload includes `common_features`, `provider_features`, `source_confidence` and `freshness`.
- Confirm `common_features` covers sleep, sleep timing, recovery, activity, strain/load, stress proxy, freshness, coverage and confidence.
- Confirm Apple-only fields stay under `provider_features.apple_health`.
- Confirm `wearable_feature_snapshots` receives one row after migration `005_wearable_platform.sql` is applied.
- Confirm `privacy_raw_health_samples_sent=false`.
- Confirm no exact sleep stage timestamps are sent.

Analytics checks:

- `wearable_connect_started`
- `wearable_connected`
- `wearable_data_available`
- `wearable_data_stale`
- `permission_requested`
- `permission_granted`
- `health_data_available`
- `stale_health_data`
- `proactive_health_alert`

## Android Health Connect

Device setup:

- Install the latest internal/closed test build on a real Android device.
- Install or enable Health Connect.
- Connect at least one real source: Fitbit, Garmin, Samsung Health, Google Fit bridge, Oura, WHOOP, or compatible source.

Checks:

- Grant all Health Connect permissions.
- Reopen Blanked and open Stats.
- Confirm `Health Sources` shows one of: `Connected`, `No data`, `Stale`, `Partial`, `Not connected`, or `Unavailable`.
- Confirm visible metrics when available: sleep, steps, distance, calories, elevation/floors, workouts, mindfulness, HR, resting HR, HRV, respiratory rate, oxygen saturation and VO2 max.
- Grant only part of the permission set and confirm `Partial permission` appears.
- Confirm recovery score/freshness/coverage affect the local AI plan but do not block app usage.
- Confirm the app works normally without Health Connect or without a wearable.

Payload checks:

- Submit AI report sync.
- Confirm backend receives aggregated feature totals/averages only.
- Confirm payload includes `common_features`, `provider_features`, `source_confidence` and `freshness`.
- Confirm Health Connect-only fields stay under `provider_features.health_connect`.
- Confirm `wearable_feature_snapshots` receives one row after migration `005_wearable_platform.sql` is applied.
- Confirm `raw_health_samples_sent=false`.

Analytics checks:

- `wearable_connect_started`
- `wearable_connected`
- `wearable_data_available`
- `wearable_data_stale`
- `permission_requested`
- `permission_granted`
- `health_data_available`
- `stale_health_data`

## Direct API Platform

Backend setup:

- Apply `supabase/migrations/005_wearable_platform.sql`.
- Set `WEARABLE_OAUTH_REDIRECT_BASE`.
- Set `WEARABLE_OAUTH_STATE_SECRET`.
- Set `WEARABLE_TOKEN_ENCRYPTION_KEY`.
- Configure provider credentials only for providers being tested:
  - `OURA_CLIENT_ID` / `OURA_CLIENT_SECRET`
  - `WHOOP_CLIENT_ID` / `WHOOP_CLIENT_SECRET`
  - `FITBIT_CLIENT_ID` / `FITBIT_CLIENT_SECRET`
  - `WITHINGS_CLIENT_ID` / `WITHINGS_CLIENT_SECRET`
- Treat Garmin as blocked until Garmin partner access is approved.

Connection endpoint checks:

- POST `wearable-connections` with `action=list` returns current sources.
- POST `wearable-connections` with `action=upsert_aggregator` stores Apple Health / Health Connect status.
- POST `wearable-connections` with `action=disconnect` clears tokens and marks the provider disconnected.

OAuth checks:

- POST `wearable-oauth-start` returns `authorization_url` for Oura, WHOOP, Fitbit/Google Health or Withings when credentials exist.
- `wearable-oauth-callback` exchanges `code`, encrypts tokens and stores `wearable_connections.status=connected`.
- Callback stores `external_account_hash`, never the external account id in clear text.
- Missing credentials return `provider_oauth_not_configured`.
- Garmin returns `provider_requires_partner_access`.

Sync checks:

- POST `wearable-sync` with `sync_kind=initial_30d` stores a 30-day `wearable_feature_snapshots` row.
- POST `wearable-sync` with `sync_kind=incremental` stores a 7-day snapshot and updates `last_sync_at`.
- Failed provider calls set `wearable_connections.status=error` and `last_error`.
- Snapshot includes `common_features`, provider-specific `provider_features`, `source_confidence` and `freshness`.
- POST `wearable-outcome` records generated, accepted, ignored, dismissed, completed and failed recommendation outcomes.
- New `digital-wellness-features` insights include recent wearable memory when outcomes exist.

## Exit Criteria

- No crashes on denied, partial, stale or empty states.
- Permissions are understandable before the platform sheet opens.
- Real wearable data visibly improves plan/report context.
- Backend payload contains no raw samples.
- Source confidence and freshness are visible in stored payloads.
- Direct OAuth stores encrypted tokens only.
- Direct APIs remain deferred until QA proves an aggregator gap.
