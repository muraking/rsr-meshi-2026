create extension if not exists pgcrypto;

create table if not exists public.location_groups (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.location_group_members (
  user_id uuid not null,
  group_id uuid not null references public.location_groups(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

alter table public.location_groups enable row level security;
alter table public.location_group_members enable row level security;

drop policy if exists "users view own memberships" on public.location_group_members;
create policy "users view own memberships"
on public.location_group_members for select to authenticated
using (user_id=auth.uid());

alter table public.location_pins
add column if not exists group_id uuid references public.location_groups(id) on delete cascade;

delete from public.location_pins where group_id is null;
alter table public.location_pins alter column group_id set not null;

drop policy if exists "everyone can view pins" on public.location_pins;
drop policy if exists "users create own pins" on public.location_pins;
drop policy if exists "users delete own pins" on public.location_pins;

create policy "group members view pins"
on public.location_pins for select to authenticated
using (exists (
  select 1 from public.location_group_members member
  where member.user_id=auth.uid() and member.group_id=location_pins.group_id
));

create policy "group members create own pins"
on public.location_pins for insert to authenticated
with check (auth.uid()=user_id and exists (
  select 1 from public.location_group_members member
  where member.user_id=auth.uid() and member.group_id=location_pins.group_id
));

create policy "users delete own pins"
on public.location_pins for delete to authenticated
using (auth.uid()=user_id);

create or replace function public.join_location_group(input_code text)
returns uuid
language plpgsql
security definer
set search_path=public
as $function$
declare
  normalized_code text;
  wanted_hash text;
  wanted_group uuid;
begin
  normalized_code=upper(trim(input_code));
  if char_length(normalized_code) < 4 or char_length(normalized_code) > 30 then
    raise exception 'group code must be between 4 and 30 characters';
  end if;
  wanted_hash=encode(extensions.digest(normalized_code,'sha256'),'hex');
  insert into public.location_groups(code_hash) values(wanted_hash)
  on conflict(code_hash) do nothing;
  select id into wanted_group from public.location_groups where code_hash=wanted_hash;
  insert into public.location_group_members(user_id,group_id) values(auth.uid(),wanted_group)
  on conflict do nothing;
  return wanted_group;
end;
$function$;

revoke all on function public.join_location_group(text) from public;
grant execute on function public.join_location_group(text) to authenticated;

create or replace function public.limit_location_pins()
returns trigger
language plpgsql
security definer
set search_path=public
as $function$
begin
  if (select count(*) from public.location_pins where user_id=new.user_id and group_id=new.group_id) >= 5 then
    delete from public.location_pins
    where id=(
      select id from public.location_pins
      where user_id=new.user_id and group_id=new.group_id
      order by created_at asc limit 1
    );
  end if;
  return new;
end;
$function$;
