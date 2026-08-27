create or replace view funnel_events as
select
  id,
  anonymous_user_id,
  submitted_at,
  platform,
  locale,
  app_version,
  build_number,
  payload->>'event' as event_name,
  payload->>'step' as step_name,
  payload->'properties' as properties,
  data_consent,
  consent_text
from digital_wellness_feature_payloads
where payload ? 'event';

create or replace view funnel_metrics_daily as
select
  date_trunc('day', submitted_at) as day,
  platform,
  app_version,
  build_number,
  event_name,
  step_name,
  count(*) as event_count,
  count(distinct anonymous_user_id) as user_count
from funnel_events
group by 1, 2, 3, 4, 5, 6;

create or replace view funnel_users_daily as
select
  date_trunc('day', submitted_at) as day,
  anonymous_user_id,
  max((event_name = 'onboarding_started')::int) = 1 as onboarding_started,
  max((event_name = 'screen_time_permission_result' and properties->>'granted' = 'true')::int) = 1 as screen_time_granted,
  max((event_name = 'apps_selection_updated' and coalesce((properties->>'selection_count')::int, 0) > 0)::int) = 1 as selected_apps,
  max((event_name = 'trial_started')::int) = 1 as trial_started,
  max((event_name = 'free_plan_selected')::int) = 1 as free_plan_selected,
  max((event_name = 'first_block_started')::int) = 1 as first_block_started,
  max((event_name = 'relapse_attempt')::int) = 1 as relapse_attempted,
  max((event_name = 'ai_insight_received')::int) = 1 as ai_insight_received
from funnel_events
group by 1, 2;
