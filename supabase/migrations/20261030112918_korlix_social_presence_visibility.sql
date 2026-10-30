-- Change only the authenticated actor's presence preference. Heartbeats from
-- older clients must preserve explicit offline choices, including other devices.
do $migration$
declare
 definition text := pg_get_functiondef('public.korlix_social_v1(uuid,text,jsonb)'::regprocedure);
 old_block text := $old$ if p_action='presence' then
  update korlix_social_profiles set last_seen=case when p_data->'active'='true'::jsonb and show_online then now() else null end where id=me.id;
  return jsonb_build_object('ok',true);
 end if;$old$;
 new_block text := $new$ if p_action='presence' then
  if jsonb_typeof(p_data->'active') is distinct from 'boolean'
     or (p_data ? 'show_online' and jsonb_typeof(p_data->'show_online') is distinct from 'boolean') then
   raise exception 'Presence settings must be true or false';
  end if;
  update korlix_social_profiles
   set show_online=coalesce((p_data->>'show_online')::boolean,show_online),
       last_seen=case when p_data->'active'='true'::jsonb
         and coalesce((p_data->>'show_online')::boolean,show_online) then now() else null end
   where id=me.id returning * into me;
  return jsonb_build_object('ok',true,'show_online',me.show_online,
   'online',coalesce(me.show_online and me.last_seen>now()-interval '90 seconds',false));
 end if;$new$;
begin
 if position(old_block in definition)=0 then
  raise exception 'Unexpected Social presence implementation; review before applying';
 end if;
 execute replace(definition,old_block,new_block);
end;
$migration$;
