-- Applied migration 20260919155618. Zoom issues the singular transcript scope.
-- Correct only this exact check;
-- preserve function privileges, host proof, account binding, and consent.
do $migration$
declare
  definition text;
  old_check constant text := $old$'meeting:read:meeting_transcripts'=any(regexp_split_to_array(v->>'scope',' +'))$old$;
  new_check constant text := $new$'meeting:read:meeting_transcript'=any(regexp_split_to_array(v->>'scope',' +'))$new$;
begin
  definition := pg_get_functiondef('public.k135z_b5b_storage_v1(text,jsonb)'::regprocedure);
  if (length(definition)-length(replace(definition,old_check,'')))/length(old_check) <> 1
     or position(new_check in definition) <> 0 then
    raise exception 'K135Z_TRANSCRIPT_SCOPE_SOURCE_CHANGED';
  end if;
  execute replace(definition,old_check,new_check);
end
$migration$;
