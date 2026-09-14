-- Keep repeated dashboard refreshes from inflating the learning sample.
create unique index if not exists bai_user_plan_outcomes_generated_key_idx
  on bai_user_plan_outcomes(anonymous_user_id, (metadata->>'generated_key'))
  where outcome = 'generated' and metadata ? 'generated_key';

-- A user can revise feedback, but the same label for the same recommendation
-- should not create multiple identical learning events.
create unique index if not exists bai_recommendation_feedback_recommendation_type_idx
  on bai_recommendation_feedback(anonymous_user_id, recommendation_id, feedback_type)
  where recommendation_id is not null;
