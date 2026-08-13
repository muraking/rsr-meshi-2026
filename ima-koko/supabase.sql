create table public.location_pins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  display_name text not null check (char_length(display_name) between 1 and 20),
  x real not null check (x between 0 and 2072),
  y real not null check (y between 0 and 1910),
  created_at timestamptz not null default now()
);

alter table public.location_pins enable row level security;
create policy "everyone can view pins" on public.location_pins for select to authenticated using (true);
create policy "users create own pins" on public.location_pins for insert to authenticated with check (auth.uid() = user_id);
create policy "users delete own pins" on public.location_pins for delete to authenticated using (auth.uid() = user_id);

create or replace function public.limit_location_pins() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if (select count(*) from public.location_pins where user_id=new.user_id) >= 5 then
    delete from public.location_pins
    where id=(select id from public.location_pins where user_id=new.user_id order by created_at asc limit 1);
  end if;
  return new;
end;
$$;
create trigger enforce_location_pin_limit before insert on public.location_pins for each row execute function public.limit_location_pins();

alter publication supabase_realtime add table public.location_pins;
