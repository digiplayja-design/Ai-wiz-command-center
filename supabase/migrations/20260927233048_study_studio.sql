-- Private study packs and progress. The verified backend is the only caller.
create table public.korlix_study_sets(
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 state text not null check(state in('preparing','ready','failed','deleted')),
 source text not null check(source in('ai','starter')), input jsonb not null default '{}',
 request_hash text not null, lesson jsonb not null default '{}',
 progress jsonb not null default '{"read":{},"cards":{},"answers":{}}',
 revision integer not null default 0, last_event_id uuid, last_event_hash text,
 usage_id uuid references public.usage_counters(id) on delete set null,
 charged integer not null default 0 check(charged in(0,1)), error text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.korlix_study_sets enable row level security;
revoke all on public.korlix_study_sets from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_study_sets to service_role;
create index korlix_study_owner_created on public.korlix_study_sets(owner_id,created_at desc);
create index korlix_study_owner_active on public.korlix_study_sets(owner_id,updated_at desc) where state<>'deleted';
create index korlix_study_usage on public.korlix_study_sets(usage_id) where usage_id is not null;
create or replace function public.korlix_study_studio_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.korlix_study_sets; old public.korlix_study_sets; h text; uid uuid;
 n integer; choice integer; a jsonb; p jsonb; days integer; event text; card_data jsonb;
begin
 if p_actor is null then raise exception 'Sign in to use Study Studio.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('study:'||p_actor::text,0));
 for old in select * from public.korlix_study_sets where owner_id=p_actor and state='preparing' and created_at<now()-interval '12 minutes' for update loop
  if old.charged=1 then
   update public.usage_counters set credits_used=greatest(coalesce(credits_used,0)-1,0),standard_generations=greatest(coalesce(standard_generations,0)-1,0),updated_at=now() where id=old.usage_id and user_id=p_actor;
  end if;
  update public.korlix_study_sets set state='failed',charged=0,input=input-'notes',error='This study pack was interrupted. Your credit was returned. Create a new pack to try again.',updated_at=now() where id=old.id;
 end loop;
 if p_action='list' then
  return jsonb_build_object('sets',coalesce((select jsonb_agg(
   jsonb_build_object('id',x.id,'state',x.state,'source',x.source,'details',x.input-'notes','title',x.lesson->>'title','progress',x.progress,'cardCount',coalesce(jsonb_array_length(x.lesson->'cards'),0),'questionCount',coalesce(jsonb_array_length(x.lesson->'quiz'),0),'sectionCount',coalesce(jsonb_array_length(x.lesson->'sections'),0),'updated_at',x.updated_at)
   order by x.updated_at desc,x.id) from public.korlix_study_sets x where x.owner_id=p_actor and x.state<>'deleted'),'[]'));
 end if;
 if p_action in('create','lookup') then
  h:=encode(sha256(convert_to((p_data->'input')::text,'UTF8')),'hex');
  select * into s from public.korlix_study_sets where id=p_id and owner_id=p_actor for update;
  if found then
   if s.request_hash is distinct from h or s.state='deleted' then raise exception 'Use a new request after changing your topic or notes.' using errcode='40001';end if;
   return (to_jsonb(s)-'owner_id'-'request_hash'-'usage_id'-'last_event_id'-'last_event_hash'-'input')||jsonb_build_object('details',s.input-'notes','replayed',true);
  end if;
  if p_action='lookup' then raise exception 'Study pack not found.' using errcode='P0002';end if;
  if (select count(*) from public.korlix_study_sets where owner_id=p_actor and state<>'deleted')>=50 then raise exception 'You have 50 study packs. Remove one before creating another.' using errcode='54000';end if;
  if (select count(*) from public.korlix_study_sets where owner_id=p_actor and created_at>now()-interval '1 hour')>=40 then raise exception 'Please wait before creating more study packs.' using errcode='54000';end if;
  if p_data->'input'->>'starter' is null then
   if exists(select 1 from public.korlix_study_sets where owner_id=p_actor and state='preparing') then raise exception 'A study pack is already being prepared. Open My learning to follow it.' using errcode='40001';end if;
   if (select count(*) from public.korlix_study_sets where owner_id=p_actor and source='ai' and created_at>now()-interval '1 hour')>=12 then raise exception 'Please wait before requesting more AI study packs.' using errcode='54000';end if;
   uid:=(p_data->>'usage_id')::uuid;
   perform 1 from public.usage_counters where id=uid and user_id=p_actor for update;
   if not found then raise exception 'Usage could not be verified.' using errcode='40001';end if;
   if (p_data->>'credit_limit')::integer is null or (p_data->>'request_limit')::integer is null then raise exception 'Usage limits could not be verified.' using errcode='42501';end if;
   update public.usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now()
    where id=uid and user_id=p_actor and coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;
   if not found then raise exception 'Your daily generation allowance is used. Try again when it renews.' using errcode='54000';end if;
   insert into public.korlix_study_sets(id,owner_id,state,source,input,request_hash,usage_id,charged) values(p_id,p_actor,'preparing','ai',p_data->'input',h,uid,1) returning * into s;
  else
   insert into public.korlix_study_sets(id,owner_id,state,source,input,request_hash,lesson) values(p_id,p_actor,'ready','starter',p_data->'input',h,p_data->'lesson') returning * into s;
  end if;
  return (to_jsonb(s)-'owner_id'-'request_hash'-'usage_id'-'last_event_id'-'last_event_hash'-'input')||jsonb_build_object('details',s.input-'notes','replayed',false);
 end if;
 select * into s from public.korlix_study_sets where id=p_id and owner_id=p_actor for update;
 if not found or s.state='deleted' then
  if p_action='remove' and s.state='deleted' then return jsonb_build_object('removed',true);end if;
  raise exception 'Study pack not found.' using errcode='P0002';
 end if;
 if p_action in('finish','fail') then
  if s.state='preparing' then
   if p_action='fail' then
    if s.charged=1 then update public.usage_counters set credits_used=greatest(coalesce(credits_used,0)-1,0),standard_generations=greatest(coalesce(standard_generations,0)-1,0),updated_at=now() where id=s.usage_id and user_id=p_actor;end if;
    update public.korlix_study_sets set state='failed',charged=0,input=input-'notes',error=left(p_data->>'error',400),updated_at=now() where id=s.id returning * into s;
   else
    update public.korlix_study_sets set state='ready',input=input-'notes',lesson=p_data->'lesson',updated_at=now() where id=s.id returning * into s;
   end if;
  end if;
 elsif p_action='remove' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before deleting this study pack.';end if;
  if s.state='preparing' then raise exception 'Wait for the study pack to finish before deleting it.' using errcode='40001';end if;
  update public.korlix_study_sets set state='deleted',input='{}',lesson='{}',progress='{}',error=null,last_event_id=null,last_event_hash=null,updated_at=now() where id=s.id;
  return jsonb_build_object('removed',true);
 elsif p_action='progress' then
  if s.state<>'ready' then raise exception 'Wait until the study pack is ready.' using errcode='40001';end if;
  h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  if s.last_event_id=(p_data->>'request_key')::uuid then
   if s.last_event_hash is distinct from h then raise exception 'Use a new request for a different answer.' using errcode='40001';end if;
  else
   if s.revision is distinct from (p_data->>'revision')::integer then raise exception 'Your progress changed elsewhere. Refresh this pack before continuing.' using errcode='40001';end if;
   event:=p_data->>'event';n:=(p_data->>'index')::integer;p:=s.progress;
   if event='read' then
    if n is null or n<0 or n>=jsonb_array_length(s.lesson->'sections') then raise exception 'Choose a lesson section.';end if;
    p:=jsonb_set(p,array['read',n::text],'true');
   elsif event='card' then
    if n is null or n<0 or n>=jsonb_array_length(s.lesson->'cards') or p_data->>'rating' is null or p_data->>'rating' not in('again','known') then raise exception 'Choose a flashcard rating.';end if;
    card_data:=coalesce(p->'cards'->n::text,'{}');
    days:=case when p_data->>'rating'='again' then 0 when coalesce((card_data->>'days')::integer,0)=0 then 1 when (card_data->>'days')::integer=1 then 3 when (card_data->>'days')::integer=3 then 7 else least(30,(card_data->>'days')::integer*2) end;
    p:=jsonb_set(p,array['cards',n::text],jsonb_build_object('rating',p_data->>'rating','days',days,'due',case when days=0 then now()+interval '10 minutes' else now()+make_interval(days=>days) end));
   elsif event='answer' then
    choice:=(p_data->>'choice')::integer;
    if n is null or n<0 or n>=jsonb_array_length(s.lesson->'quiz') or choice is null or choice<0 or choice>3 then raise exception 'Choose an available answer.';end if;
    a:=p->'answers'->n::text;
    if a is not null and (a->>'choice')::integer=(s.lesson->'quiz'->n->>'answer')::integer then raise exception 'This question is complete. Restart the quiz to practice it again.' using errcode='40001';end if;
    p:=jsonb_set(p,array['answers',n::text],jsonb_build_object('choice',choice,'firstChoice',coalesce((a->>'firstChoice')::integer,choice),'attempts',least(100,coalesce((a->>'attempts')::integer,0)+1)));
   elsif event='resetQuiz' then
    if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before restarting the quiz.';end if;
    p:=jsonb_set(p,'{answers}','{}');
   else raise exception 'Unknown study progress action.';end if;
   update public.korlix_study_sets set progress=p,revision=revision+1,last_event_id=(p_data->>'request_key')::uuid,last_event_hash=h,updated_at=now() where id=s.id returning * into s;
  end if;
 elsif p_action<>'get' then raise exception 'Unknown study action.';
 end if;
 return (to_jsonb(s)-'owner_id'-'request_hash'-'usage_id'-'last_event_id'-'last_event_hash'-'input')||jsonb_build_object('details',s.input-'notes');
end $$;
revoke all on function public.korlix_study_studio_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_study_studio_v1(uuid,text,uuid,jsonb) to service_role;
