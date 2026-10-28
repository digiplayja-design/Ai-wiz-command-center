-- Service-only storage: browser and Supabase user tokens cannot access credentials.
create table public.korlix_auto_email_mailboxes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 agent_id text not null check (agent_id ~ '^[a-z][a-z0-9_]{0,95}$'),
 provider text not null check (provider in ('google','microsoft')),
 generation bigint not null default 0,
 status text not null default 'disconnected' check (status in ('connected','disconnected')),
 identity jsonb,
 secrets jsonb,
 scopes jsonb not null default '[]',
 connected_at timestamptz,
 updated_at timestamptz not null default now(),
 unique(user_id,agent_id,provider),
 check ((status='connected' and identity is not null and secrets is not null) or (status='disconnected' and secrets is null))
);
create table public.korlix_auto_email_mailbox_flows (
 id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 agent_id text not null check (agent_id ~ '^[a-z][a-z0-9_]{0,95}$'),
 provider text not null check (provider in ('google','microsoft')),
 device_hash text not null check (device_hash ~ '^[a-f0-9]{64}$'),
 generation bigint not null,
 state_hash text unique check (state_hash ~ '^[a-f0-9]{64}$'),
 browser_hash text check (browser_hash ~ '^[a-f0-9]{64}$'),
 status text not null check (status in ('pending','exchanging','review','error','confirmed','cancelled','expired')),
 secrets jsonb,
 identity jsonb,
 scopes jsonb not null default '[]',
 error_code text,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 foreign key(user_id,agent_id,provider) references public.korlix_auto_email_mailboxes(user_id,agent_id,provider) on delete cascade
);
create index korlix_auto_email_mailbox_flow_owner on public.korlix_auto_email_mailbox_flows(user_id,agent_id,provider);
create index korlix_auto_email_mailbox_flow_expiry on public.korlix_auto_email_mailbox_flows(expires_at);
alter table public.korlix_auto_email_mailboxes enable row level security;
alter table public.korlix_auto_email_mailbox_flows enable row level security;
revoke all on public.korlix_auto_email_mailboxes,public.korlix_auto_email_mailbox_flows from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_auto_email_mailboxes,public.korlix_auto_email_mailbox_flows to service_role;

-- All mutations lock the mailbox first. A new attempt or disconnect increments
-- its generation, making every earlier callback/confirmation incapable of revival.
create function public.korlix_auto_email_mailbox_begin(p_flow jsonb) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_auto_email_mailbox_flows; g bigint;
begin
 f:=jsonb_populate_record(null::public.korlix_auto_email_mailbox_flows,p_flow);
 if f.secrets is null or f.state_hash is null or f.browser_hash is null then raise exception 'invalid mailbox attempt'; end if;
 insert into public.korlix_auto_email_mailboxes(user_id,agent_id,provider) values(f.user_id,f.agent_id,f.provider) on conflict(user_id,agent_id,provider) do nothing;
 update public.korlix_auto_email_mailboxes set generation=generation+1,updated_at=now() where user_id=f.user_id and agent_id=f.agent_id and provider=f.provider returning generation into g;
 update public.korlix_auto_email_mailbox_flows set status='cancelled',secrets=null,identity=null,state_hash=null,browser_hash=null
 where user_id=f.user_id and agent_id=f.agent_id and provider=f.provider and status in ('pending','exchanging','review');
 insert into public.korlix_auto_email_mailbox_flows(id,user_id,agent_id,provider,device_hash,generation,state_hash,browser_hash,status,secrets,created_at,expires_at)
 values(f.id,f.user_id,f.agent_id,f.provider,f.device_hash,g,f.state_hash,f.browser_hash,'pending',f.secrets,now(),now()+interval '10 minutes');
 return jsonb_build_object('id',f.id,'expiresAt',now()+interval '10 minutes');
end $$;

create function public.korlix_auto_email_mailbox_confirm(p_user uuid,p_agent text,p_device text,p_flow uuid,p_secrets jsonb) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_auto_email_mailbox_flows; m public.korlix_auto_email_mailboxes;
begin
 select * into f from public.korlix_auto_email_mailbox_flows where id=p_flow and user_id=p_user and agent_id=p_agent and device_hash=p_device;
 if not found then return jsonb_build_object('confirmed',false); end if;
 select * into m from public.korlix_auto_email_mailboxes where user_id=p_user and agent_id=p_agent and provider=f.provider for update;
 select * into f from public.korlix_auto_email_mailbox_flows where id=p_flow and user_id=p_user and agent_id=p_agent and device_hash=p_device for update;
 if f.status<>'review' or f.expires_at<=now() or f.generation<>m.generation or f.identity is null or f.secrets is null or p_secrets is null then return jsonb_build_object('confirmed',false); end if;
 update public.korlix_auto_email_mailboxes set status='connected',identity=f.identity,secrets=p_secrets,scopes=f.scopes,connected_at=now(),updated_at=now() where id=m.id;
 update public.korlix_auto_email_mailbox_flows set status='confirmed',secrets=null,identity=null,state_hash=null,browser_hash=null where id=f.id;
 return jsonb_build_object('confirmed',true,'provider',f.provider,'identity',f.identity);
end $$;

create function public.korlix_auto_email_mailbox_disconnect(p_user uuid,p_agent text,p_provider text) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 insert into public.korlix_auto_email_mailboxes(user_id,agent_id,provider) values(p_user,p_agent,p_provider) on conflict(user_id,agent_id,provider) do nothing;
 update public.korlix_auto_email_mailboxes set status='disconnected',generation=generation+1,identity=null,secrets=null,scopes='[]',connected_at=null,updated_at=now() where user_id=p_user and agent_id=p_agent and provider=p_provider;
 update public.korlix_auto_email_mailbox_flows set status='cancelled',secrets=null,identity=null,state_hash=null,browser_hash=null where user_id=p_user and agent_id=p_agent and provider=p_provider and status in ('pending','exchanging','review');
 return jsonb_build_object('disconnected',true);
end $$;

create function public.korlix_auto_email_mailbox_cleanup() returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 update public.korlix_auto_email_mailbox_flows set status='expired',secrets=null,identity=null,state_hash=null,browser_hash=null where expires_at<=now() and status in ('pending','exchanging','review');
 delete from public.korlix_auto_email_mailbox_flows where expires_at<now()-interval '1 day';
end $$;

revoke all on function public.korlix_auto_email_mailbox_begin(jsonb) from public,anon,authenticated;
revoke all on function public.korlix_auto_email_mailbox_confirm(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.korlix_auto_email_mailbox_disconnect(uuid,text,text) from public,anon,authenticated;
revoke all on function public.korlix_auto_email_mailbox_cleanup() from public,anon,authenticated;
grant execute on function public.korlix_auto_email_mailbox_begin(jsonb) to service_role;
grant execute on function public.korlix_auto_email_mailbox_confirm(uuid,text,text,uuid,jsonb) to service_role;
grant execute on function public.korlix_auto_email_mailbox_disconnect(uuid,text,text) to service_role;
grant execute on function public.korlix_auto_email_mailbox_cleanup() to service_role;
