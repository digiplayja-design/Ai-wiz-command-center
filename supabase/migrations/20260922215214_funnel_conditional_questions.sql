begin;
-- The capture transaction and stored answers are unchanged; replace only its
-- private validator after confirming the reviewed K153 definition is present.
do $$ begin
 if (select md5(prosrc) from pg_proc where oid='public.korlix_funnel_answers_v1(jsonb,jsonb)'::regprocedure) is distinct from '74844b2a09ff397b09fe7706aa3650ab' then
  raise exception 'The answer validator changed. Review K154 before applying.';
 end if;
end $$;
create or replace function public.korlix_funnel_answers_v1(p_document jsonb,p_answers jsonb)
returns jsonb language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare qs jsonb:=coalesce(p_document->'questions','[]'); supplied jsonb:=coalesce(p_answers,'[]');
 q jsonb; a jsonb; v text; rule jsonb; source jsonb; result jsonb:='[]'; definitions jsonb:='[]'; seen text[]:='{}';
begin
 if jsonb_typeof(qs) is distinct from 'array' or jsonb_typeof(supplied) is distinct from 'array' then raise exception 'Check the inquiry answers.'; end if;
 if jsonb_array_length(qs)>4 or jsonb_array_length(supplied)>4 then raise exception 'Complete the inquiry questions.'; end if;
 if exists(select 1 from jsonb_array_elements(supplied) x where jsonb_typeof(x) is distinct from 'object' or jsonb_typeof(x->'id') is distinct from 'string')
   or (select count(distinct x->>'id') from jsonb_array_elements(supplied) x)<>jsonb_array_length(supplied) then raise exception 'Check the inquiry answers.'; end if;
 for q in select value from jsonb_array_elements(qs) loop
  if jsonb_typeof(q) is distinct from 'object' or jsonb_typeof(q->'id') is distinct from 'string'
    or q->>'id' !~ '^q-[1-4]$' or q->>'id'=any(seen)
    or coalesce(q->>'type','') not in ('text','choice') or jsonb_typeof(q->'required') is distinct from 'boolean'
    or jsonb_typeof(q->'label') is distinct from 'string' or length(trim(q->>'label')) not between 1 and 120
    or (q->>'label') ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' then raise exception 'This form needs its questions completed.'; end if;
  seen:=array_append(seen,q->>'id');
  if q->>'type'='choice' then
   if jsonb_typeof(q->'options') is distinct from 'array' then raise exception 'Check the question choices.'; end if;
   if jsonb_array_length(q->'options') not between 2 and 8
    or exists(select 1 from jsonb_array_elements(q->'options') x where jsonb_typeof(x) is distinct from 'string' or length(trim(x#>>'{}')) not between 1 and 80)
    or (select count(distinct value) from jsonb_array_elements(q->'options'))<>jsonb_array_length(q->'options') then raise exception 'Check the question choices.'; end if;
  end if;
  rule:=q->'show_when';
  if rule is not null and rule<>'null'::jsonb then
   if jsonb_typeof(rule) is distinct from 'object' or jsonb_typeof(rule->'question_id') is distinct from 'string'
    or jsonb_typeof(rule->'equals') is distinct from 'string' or length(trim(rule->>'equals')) not between 1 and 80 then raise exception 'Check the question condition.'; end if;
   select value into source from jsonb_array_elements(definitions) where value->>'id'=rule->>'question_id';
   if source is null or source->>'type'<>'choice' or not exists(select 1 from jsonb_array_elements_text(source->'options') o where o=rule->>'equals') then raise exception 'Choose an earlier multiple-choice question and a current choice.'; end if;
  end if;
  definitions:=definitions||jsonb_build_array(q);
  if rule is not null and rule<>'null'::jsonb and not exists(select 1 from jsonb_array_elements(result) x where x->>'id'=rule->>'question_id' and x->>'value'=rule->>'equals') then continue; end if;
  if (select count(*) from jsonb_array_elements(supplied) x where x->>'id'=q->>'id')<>1 then raise exception 'Check the inquiry answers.'; end if;
  select value into a from jsonb_array_elements(supplied) where value->>'id'=q->>'id';
  if jsonb_typeof(a->'value') is distinct from 'string' then raise exception 'Check the inquiry answers.'; end if;
  v:=trim(a->>'value');
  if length(v)>(case when q->>'type'='choice' then 80 else 500 end)
    or v ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' or ((q->>'required')::boolean and v='') then raise exception 'Complete the required inquiry answers.'; end if;
  if q->>'type'='choice' and v<>'' and not exists(select 1 from jsonb_array_elements_text(q->'options') o where o=v) then raise exception 'Choose one of the listed answers.'; end if;
  -- Labels and types come only from the locked published document, never the visitor.
  result:=result||jsonb_build_array(jsonb_build_object('id',q->>'id','label',q->>'label','type',q->>'type','value',v));
 end loop;
 if exists(select 1 from jsonb_array_elements(supplied) x where not (x->>'id'=any(seen))) then raise exception 'Check the inquiry answers.'; end if;
 return result;
end $$;
revoke all on function public.korlix_funnel_answers_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_answers_v1(jsonb,jsonb) to service_role;

commit;
