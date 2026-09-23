begin;
create table public.korlix_funnel_meta_campaign_links (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  version integer not null default 1 check(version>0),
  account_id text check(account_id ~ '^act_[0-9]{1,40}$'),
  provider_campaign_id text check(provider_campaign_id ~ '^[0-9]{1,40}$'),
  provider_campaign_name text check(length(trim(provider_campaign_name)) between 1 and 1000),
  account_snapshot jsonb,
  binding_id uuid,
  config_hash text,
  linked_at timestamptz,
  updated_at timestamptz not null default now(),
  check((account_id is null and provider_campaign_id is null and provider_campaign_name is null and account_snapshot is null and binding_id is null and config_hash is null and linked_at is null)
    or (account_id is not null and provider_campaign_id is not null and provider_campaign_name is not null and account_snapshot is not null and jsonb_typeof(account_snapshot)='object' and account_snapshot->>'id' is not null and account_snapshot->>'id'=account_id and binding_id is not null and config_hash is not null and linked_at is not null)),
  unique(user_id,account_id,provider_campaign_id)
);
alter table public.korlix_funnel_meta_campaign_links enable row level security;
revoke all on public.korlix_funnel_meta_campaign_links from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_meta_campaign_links to service_role;
comment on table public.korlix_funnel_meta_campaign_links is 'Private owner-selected Meta campaign associations, not verified conversion attribution. One provider campaign per owner/account may link to one local plan. Cleared rows retain versions. No credentials, receipts or performance metrics are stored.';

create function public.korlix_funnel_meta_campaign_link_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; m public.korlix_meta_connections; w public.korlix_funnel_meta_campaign_links;
  account jsonb; fingerprint text; ready boolean; current_link boolean; configured boolean; out jsonb;
  first_day date; last_day date; report_days integer; first_instant timestamptz; end_instant timestamptz; tagged bigint;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Meta campaign links require Enterprise.' using errcode='42501'; end if;
  if p_action is null or p_action not in ('read','save','clear','measure') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose a supported Meta campaign link action.'; end if;
  if jsonb_typeof(p_data->'campaign_id') is distinct from 'string' or coalesce(p_data->>'campaign_id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'Choose a campaign plan.'; end if;
  if jsonb_typeof(p_data->'configured') is distinct from 'boolean' or jsonb_typeof(p_data->'config_hash') is distinct from 'string' or coalesce(p_data->>'config_hash','') !~ '^[a-f0-9]{64}$' then raise exception 'Campaign link configuration is unavailable.'; end if;
  if exists(select 1 from jsonb_object_keys(p_data) k where k <> all(case p_action
    when 'read' then array['campaign_id','configured','config_hash']
    when 'save' then array['campaign_id','configured','config_hash','version','fingerprint','provider_campaign_id','provider_campaign_name','confirmed']
    when 'clear' then array['campaign_id','configured','config_hash','version','fingerprint','confirmed']
    else array['campaign_id','configured','config_hash','fingerprint','days','from','to'] end)) then raise exception 'Unexpected Meta campaign link fields.'; end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  if c.platform<>'meta' then raise exception 'Choose a Meta campaign plan.'; end if;
  select * into m from public.korlix_meta_connections where user_id=p_actor for share;
  select * into w from public.korlix_funnel_meta_campaign_links where campaign_id=c.id for update;
  select jsonb_build_object('id',x->>'id','name',x->>'name','currency',x->>'currency','timezone',x->>'timezone','status',x->'status') into account
    from jsonb_array_elements(coalesce(m.accounts,'[]')) x where x->>'id'=m.selected_account limit 1;
  configured:=(p_data->>'configured')::boolean;
  ready:=coalesce(configured and m.config_hash=p_data->>'config_hash' and not m.needs_reconnect and m.expires_at>now()+interval '60 seconds'
    and account->>'status'='1' and account->>'id' ~ '^act_[0-9]{1,40}$' and account->>'currency' ~ '^[A-Z]{3}$'
    and exists(select 1 from pg_timezone_names where name=account->>'timezone'),false);
  fingerprint:=encode(sha256(convert_to(jsonb_build_object('domain','meta-campaign-link-v1','funnel',f.id,'funnel_version',f.version,'campaign',c.id,'campaign_version',c.version,'campaign_state',c.state,
    'link_version',coalesce(w.version,0),'connection_version',m.version,'binding',m.binding_id,'account',account,'expires',m.expires_at,'stored_config',m.config_hash,'config',p_data->>'config_hash','ready',ready,'configured',configured)::text,'UTF8')),'hex');
  current_link:=coalesce(ready and w.account_id=account->>'id' and w.binding_id=m.binding_id and w.config_hash=m.config_hash
    and w.account_snapshot->>'currency'=account->>'currency' and w.account_snapshot->>'timezone'=account->>'timezone',false);
  if p_action<>'read' then
    if p_data->>'fingerprint' is distinct from fingerprint then raise exception 'The campaign, link or Meta connection changed. Reload before continuing.' using errcode='40001'; end if;
    if p_action in ('save','clear') then
      if jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,10}$' then raise exception 'Reload the Meta campaign link.'; end if;
      if (p_data->>'version')::bigint is distinct from coalesce(w.version,0) then raise exception 'The campaign link changed. Reload before continuing.' using errcode='40001'; end if;
      if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm this campaign association.'; end if;
      if p_action='save' then
        if c.state='archived' then raise exception 'Reopen this plan before linking a Meta campaign.'; end if;
        if not ready then raise exception 'Connect and select an active Meta account before linking.'; end if;
        if jsonb_typeof(p_data->'provider_campaign_id') is distinct from 'string' or coalesce(p_data->>'provider_campaign_id','') !~ '^[0-9]{1,40}$'
          or jsonb_typeof(p_data->'provider_campaign_name') is distinct from 'string' or length(trim(p_data->>'provider_campaign_name')) not between 1 and 1000 or p_data->>'provider_campaign_name'<>trim(p_data->>'provider_campaign_name') then raise exception 'Choose a reported Meta campaign.'; end if;
        -- HTTP verifies a fresh, owner/context-bound provider receipt before this
        -- service-only command. Direct service writers must preserve that boundary.
        begin
          insert into public.korlix_funnel_meta_campaign_links(campaign_id,user_id,account_id,provider_campaign_id,provider_campaign_name,account_snapshot,binding_id,config_hash,linked_at)
            values(c.id,p_actor,account->>'id',p_data->>'provider_campaign_id',p_data->>'provider_campaign_name',account,m.binding_id,m.config_hash,now())
            on conflict(campaign_id) do update set account_id=excluded.account_id,provider_campaign_id=excluded.provider_campaign_id,provider_campaign_name=excluded.provider_campaign_name,account_snapshot=excluded.account_snapshot,
              binding_id=excluded.binding_id,config_hash=excluded.config_hash,linked_at=now(),updated_at=now(),version=korlix_funnel_meta_campaign_links.version+1;
        exception when unique_violation then raise exception 'This Meta campaign is already linked to another of your plans. Clear that link first.' using errcode='40001'; end;
      else
        insert into public.korlix_funnel_meta_campaign_links(campaign_id,user_id) values(c.id,p_actor)
          on conflict(campaign_id) do update set account_id=null,provider_campaign_id=null,provider_campaign_name=null,account_snapshot=null,binding_id=null,config_hash=null,linked_at=null,version=korlix_funnel_meta_campaign_links.version+1,updated_at=now();
      end if;
      return public.korlix_funnel_meta_campaign_link_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',c.id,'configured',configured,'config_hash',p_data->>'config_hash'));
    end if;
    if not current_link then raise exception 'Select the linked Meta account or refresh the campaign association.' using errcode='40001'; end if;
    if jsonb_typeof(p_data->'days') is distinct from 'number' or coalesce(p_data->>'days','') not in ('7','30','90')
      or jsonb_typeof(p_data->'from') is distinct from 'string' or coalesce(p_data->>'from','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or jsonb_typeof(p_data->'to') is distinct from 'string' or coalesce(p_data->>'to','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Reload a completed reporting period.'; end if;
    begin first_day:=(p_data->>'from')::date;last_day:=(p_data->>'to')::date;report_days:=(p_data->>'days')::integer;
    exception when datetime_field_overflow or invalid_datetime_format then raise exception 'Reload a completed reporting period.'; end;
    if last_day is distinct from (now() at time zone (account->>'timezone'))::date-1 or first_day is distinct from last_day-(report_days-1) then raise exception 'The reporting day changed. Load the report again.' using errcode='40001'; end if;
    first_instant:=first_day::timestamp at time zone (account->>'timezone');end_instant:=(last_day+1)::timestamp at time zone (account->>'timezone');
    select count(*) into tagged from public.korlix_funnel_leads l where l.funnel_id=f.id and l.utm->>'utm_campaign'='k143_'||replace(c.id::text,'-','') and l.utm->>'utm_source'='facebook' and l.created_at>=first_instant and l.created_at<end_instant;
  end if;
  out:=jsonb_build_object('source','meta_campaign_link','funnel_id',f.id,'campaign_id',c.id,'campaign_name',c.name,'state',c.state,
    'version',coalesce(w.version,0),'fingerprint',fingerprint,'configured',configured,'editable',c.state<>'archived','lookup_ready',ready and c.state<>'archived',
    'connection_version',coalesce(m.version,0),'account',account,'link_current',current_link,'report_ready',current_link,'updated_at',w.updated_at,'checked_at',now(),
    'link',case when w.account_id is null then null else jsonb_build_object('account',w.account_snapshot,'provider_campaign_id',w.provider_campaign_id,'provider_campaign_name',w.provider_campaign_name,'linked_at',w.linked_at) end,
    'ad_publishing_ready',false,'attribution_verified',false);
  if p_action='measure' then out:=out||jsonb_build_object('measurement',jsonb_build_object('from',first_day,'to',last_day,'days',report_days,'timezone',account->>'timezone','start_inclusive',first_instant,'end_exclusive',end_instant,'tagged_inquiries',tagged,'checked_at',now())); end if;
  return out;
end $$;
revoke all on function public.korlix_funnel_meta_campaign_link_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_campaign_link_v1(uuid,text,uuid,jsonb) to service_role;
commit;
