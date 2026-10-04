-- Accept the new fixed Rici greeting and the legacy greeting during rollout.
-- Patch only the exact-text guard; retain every ownership, dispatch and usage
-- check, SECURITY INVOKER, existing function ACLs and all saved episode content.
DO $migration$
DECLARE
  definition text := pg_get_functiondef('public.korlix_pod_v1(uuid,text,uuid,jsonb)'::regprocedure);
  old_guard text := $old$turn_data->>'text' is distinct from expected_welcome$old$;
  new_guard text := $new$(turn_data->>'text' is distinct from expected_welcome and turn_data->>'text' is distinct from replace(expected_welcome, 'K-Nova', 'Rici'))$new$;
BEGIN
  IF strpos(definition, new_guard) > 0 THEN RETURN; END IF;
  IF (length(definition) - length(replace(definition, old_guard, ''))) / length(old_guard) <> 1
     OR strpos(definition, 'Hey, I’m K-Nova. Welcome to The Pod and You, with ') = 0 THEN
    RAISE EXCEPTION 'Unexpected Pod welcome guard; migration requires review';
  END IF;
  EXECUTE replace(definition, old_guard, new_guard);
END;
$migration$;
