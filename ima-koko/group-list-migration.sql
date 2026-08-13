create or replace function public.my_location_groups()
returns table(group_id uuid,group_code text,joined_at timestamptz)
language sql security definer set search_path=public
as $function$
  select g.id,coalesce(g.code_label,'（旧グループ）'),m.joined_at
  from public.location_group_members m
  join public.location_groups g on g.id=m.group_id
  where m.user_id=auth.uid()
  order by m.joined_at desc;
$function$;
revoke all on function public.my_location_groups() from public;
grant execute on function public.my_location_groups() to authenticated;
notify pgrst,'reload schema';
