-- The Devices tab lists only devices that have a history of pairing to the
-- signed-in account: the account itself had the device on one of its ponds,
-- that pond still exists, and the device sent at least one complete reading
-- there. Owning a device without such a stay (e.g. just transferred, no pond
-- yet) isn't enough, and the same rule decides who may open its history.

create or replace function public.can_view_device_history(p_device_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1
      from public.device_locations s
      join public.ponds p on p.id = s.pond_id
     where s.device_id = upper(p_device_id)
       and s.user_id = (select auth.uid())
       and public.device_stay_complete_count(s) > 0);
$$;
revoke execute on function public.can_view_device_history(text) from public, anon, authenticated;

create or replace function public.device_history_devices()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select s.device_id
    from public.device_locations s
    join public.ponds p on p.id = s.pond_id
   where s.user_id = (select auth.uid())
     and public.device_stay_complete_count(s) > 0
   group by s.device_id
   order by max(s.started_at) desc;
$$;
