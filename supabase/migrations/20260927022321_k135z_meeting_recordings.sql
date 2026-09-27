-- Recording metadata and MP3 media are server-only. The authenticated KORLIX
-- API resolves the user, Enterprise entitlement and owned agent on every call.
create table public.k135z_meeting_recordings (
  id text primary key check (id ~ '^[a-f0-9]{32}$'),
  tenant_id text not null,
  user_id text not null,
  agent_id text not null,
  context jsonb not null check (jsonb_typeof(context)='object' and octet_length(context::text)<=16384),
  process_id uuid not null,
  status text not null check (status in ('recording','saving','ready','failed','deleting')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  duration_ms integer not null default 0 check (duration_ms between 0 and 3600000),
  byte_size integer not null default 0 check (byte_size between 0 and 33554432),
  object_path text not null unique,
  end_reason text check (end_reason is null or end_reason in
    ('stopped','duration_limit','capture_ended','service_stopped','encoder_failed',
     'invalid_audio','storage_interrupted','save_failed','no_audio','start_failed','interrupted')),
  check (length(tenant_id) between 1 and 256 and length(user_id) between 1 and 256 and length(agent_id) between 1 and 256),
  check (context->>'tenantId'=tenant_id and context->>'userId'=user_id and context->>'agentId'=agent_id),
  check (context ?& array['tenantId','userId','agentId','meetingUuid','sessionId','streamId','generation']),
  check (object_path ~ '^[a-f0-9]{64}/[a-f0-9]{32}\.mp3$' and split_part(object_path,'/',2)=id||'.mp3'),
  check (status<>'ready' or (byte_size>=64 and duration_ms>0))
);
alter table public.k135z_meeting_recordings enable row level security;
revoke all on public.k135z_meeting_recordings from public,anon,authenticated;
grant select,insert,update,delete on public.k135z_meeting_recordings to service_role;
create index k135z_recording_owner_created on public.k135z_meeting_recordings
  (tenant_id,user_id,agent_id,created_at desc);
create unique index k135z_recording_one_active on public.k135z_meeting_recordings
  (tenant_id,user_id,agent_id) where status in ('recording','saving');

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('korlix-meeting-recordings','korlix-meeting-recordings',false,33554432,array['audio/mpeg']);
-- Restrictive guard also denies access if a broad permissive policy is added
-- later for a different bucket. The service role remains server-side only.
create policy k135z_recordings_server_only on storage.objects as restrictive
for all to anon,authenticated
using (bucket_id <> 'korlix-meeting-recordings')
with check (bucket_id <> 'korlix-meeting-recordings');
