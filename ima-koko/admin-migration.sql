alter table public.location_groups add column if not exists code_label text;
alter table public.location_group_members add column if not exists display_name text;

create or replace function public.join_location_group(input_code text,input_name text)
returns uuid language plpgsql security definer set search_path=public
as $function$
declare normalized_code text; wanted_hash text; wanted_group uuid;
begin
  normalized_code=upper(trim(input_code));
  if char_length(normalized_code)<4 or char_length(normalized_code)>30 then
    raise exception 'group code must be between 4 and 30 characters';
  end if;
  wanted_hash=encode(extensions.digest(normalized_code,'sha256'),'hex');
  insert into public.location_groups(code_hash,code_label) values(wanted_hash,normalized_code)
  on conflict(code_hash) do update set code_label=coalesce(location_groups.code_label,excluded.code_label)
  returning id into wanted_group;
  insert into public.location_group_members(user_id,group_id,display_name)
  values(auth.uid(),wanted_group,nullif(trim(input_name),''))
  on conflict(user_id,group_id) do update set display_name=coalesce(nullif(trim(excluded.display_name),''),location_group_members.display_name);
  return wanted_group;
end;
$function$;
revoke all on function public.join_location_group(text,text) from public;
grant execute on function public.join_location_group(text,text) to authenticated;

create or replace function public.update_location_member_name(input_group uuid,input_name text)
returns void language plpgsql security definer set search_path=public
as $function$
begin
  update public.location_group_members set display_name=left(trim(input_name),20)
  where user_id=auth.uid() and group_id=input_group;
end;
$function$;
revoke all on function public.update_location_member_name(uuid,text) from public;
grant execute on function public.update_location_member_name(uuid,text) to authenticated;

create table if not exists public.location_admin_settings(
  singleton boolean primary key default true check(singleton),
  password_hash text not null
);
alter table public.location_admin_settings enable row level security;

create or replace function public.location_admin_password_ok(input_password text)
returns boolean language sql security definer set search_path=public
as $function$
  select exists(select 1 from public.location_admin_settings where password_hash=extensions.crypt(input_password,password_hash));
$function$;
revoke all on function public.location_admin_password_ok(text) from public;

create or replace function public.admin_location_groups(input_password text)
returns table(group_id uuid,group_code text,member_count bigint,pin_count bigint)
language plpgsql security definer set search_path=public
as $function$
begin
  if not public.location_admin_password_ok(input_password) then raise exception 'invalid admin password'; end if;
  return query select g.id,coalesce(g.code_label,'（旧グループ）'),count(distinct m.user_id),count(distinct p.id)
  from public.location_groups g left join public.location_group_members m on m.group_id=g.id left join public.location_pins p on p.group_id=g.id
  group by g.id,g.code_label order by g.created_at desc;
end;
$function$;

create or replace function public.admin_location_group_members(input_password text,input_group uuid)
returns table(display_name text,joined_at timestamptz,pin_count bigint)
language plpgsql security definer set search_path=public
as $function$
begin
  if not public.location_admin_password_ok(input_password) then raise exception 'invalid admin password'; end if;
  return query select m.display_name,m.joined_at,count(p.id)
  from public.location_group_members m left join public.location_pins p on p.group_id=m.group_id and p.user_id=m.user_id
  where m.group_id=input_group group by m.user_id,m.display_name,m.joined_at order by m.joined_at;
end;
$function$;

create or replace function public.admin_delete_location_group(input_password text,input_group uuid)
returns boolean language plpgsql security definer set search_path=public
as $function$
begin
  if not public.location_admin_password_ok(input_password) then raise exception 'invalid admin password'; end if;
  delete from public.location_groups where id=input_group;
  return found;
end;
$function$;

revoke all on function public.admin_location_groups(text) from public;
revoke all on function public.admin_location_group_members(text,uuid) from public;
revoke all on function public.admin_delete_location_group(text,uuid) from public;
grant execute on function public.admin_location_groups(text) to authenticated;
grant execute on function public.admin_location_group_members(text,uuid) to authenticated;
grant execute on function public.admin_delete_location_group(text,uuid) to authenticated;
notify pgrst,'reload schema';
