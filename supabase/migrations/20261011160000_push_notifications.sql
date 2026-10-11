-- Push notifications (Firebase Cloud Messaging) for the Android app, so
-- pond alerts and updates reach the phone even when IsdaSafe isn't running.
--
-- * push_tokens: each phone's FCM token, per account. The app registers it
--   with register_push_token() while signed in with notifications on, and
--   removes it with unregister_push_token() on sign-out / switching them off.
-- * Every new notification (water alerts, pond verification, device
--   transfers) is pushed to the owner's phones by the send-push edge
--   function, queued through pg_net -- except account_* ones, which the app
--   itself creates while the user is looking at it.
--
-- Reuses the Vault secrets from 20261011150000_water_alerts.sql
-- (isdasafe_project_url, alert_sms_secret) to call the function. The
-- function needs the FCM_SERVICE_ACCOUNT secret (Firebase service account
-- key JSON); without it nothing is pushed.

create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

-- A token belongs to whoever signed in on that phone last.
create or replace function public.register_push_token(p_token text, p_platform text default 'android')
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if p_token is null or length(p_token) not between 20 and 4096 then
    raise exception 'invalid token' using errcode = '22023';
  end if;
  insert into push_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'), now())
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

create or replace function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path to 'public'
as $$
  delete from push_tokens where token = p_token and user_id = auth.uid();
$$;

revoke execute on function public.register_push_token(text, text) from public, anon;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

create or replace function public.push_new_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_url    text;
  v_secret text;
begin
  if new.type like 'account\_%'
     or not exists (select 1 from push_tokens where user_id = new.user_id) then
    return new;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'isdasafe_project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'alert_sms_secret';
  if v_url is null or v_secret is null then
    return new;
  end if;
  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/send-push',
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    )
  );
  return new;
exception when others then
  -- A push problem must never lose the notification itself.
  raise warning 'push_new_notification: %', sqlerrm;
  return new;
end;
$$;

revoke execute on function public.push_new_notification() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.push_new_notification();
