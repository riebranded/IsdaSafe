-- Water-quality alerts: when a new reading puts one of a pond's WATER
-- readings into warning or danger, the owner gets a notification (in the
-- app's list, and on the phone through the app's system notifications) and,
-- if they want it, a text message through Semaphore.
--
-- Only the water readings alert -- dissolved oxygen, water temperature, pH,
-- ammonia -- with the same limits as the app (lib/models/reading_bands.dart),
-- plus the app's "muggy night" rule (lib/models/weather_context.dart):
-- oxygen under 5 mg/L counts as a warning when it's 85%+ humid and the
-- water is 29 C+. Humidity alone never alerts.
--
-- Not spamming:
--   * one notification when a reading enters warning, another only if it
--     gets worse (danger); nothing more while it stays there;
--   * "back to normal" once it has been normal for 30 minutes, which also
--     re-arms the alert -- so a value hovering at a limit doesn't flap;
--   * at most one text per pond reading every 2 hours (a rise to danger is
--     always texted), and the edge function caps texts per account per day;
--   * readings older than 15 minutes (an offline backlog being uploaded)
--     never alert.
--
-- Texts: profiles.alert_sms = 'warning' (warning and danger, default),
-- 'critical' (danger only) or 'off'; only to a verified phone. The trigger
-- queues them through pg_net to the send-alert-sms edge function, using two
-- Vault secrets:
--   alert_sms_secret      created below; the function reads it back through
--                         alert_sms_secret() (service role only) to check
--                         the caller
--   isdasafe_project_url  set once per project, e.g.
--     select vault.create_secret('https://<ref>.supabase.co', 'isdasafe_project_url');
-- Without them the notification is still created (sms_status 'not_configured').

create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'alert_sms_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'alert_sms_secret',
      'evaluate_water_alerts() -> send-alert-sms edge function'
    );
  end if;
end;
$$;

create or replace function public.alert_sms_secret()
returns text
language sql
security definer
set search_path to ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'alert_sms_secret'
$$;

revoke execute on function public.alert_sms_secret() from public, anon, authenticated;
grant execute on function public.alert_sms_secret() to service_role;

-- New text states: queued, not set up on the server, over the daily cap.
alter table public.notifications drop constraint if exists notifications_sms_status_check;
alter table public.notifications add constraint notifications_sms_status_check
  check (sms_status = any (array['sent', 'failed', 'skipped', 'pending', 'not_configured', 'rate_limited']));

alter table public.profiles
  add column if not exists alert_sms text not null default 'warning'
  check (alert_sms in ('warning', 'critical', 'off'));

comment on column public.profiles.alert_sms is
  'Texts for pond water alerts: warning (warning + danger), critical (danger only) or off';

-- Where each pond reading stands, so alerts fire on changes only.
create table if not exists public.pond_alert_state (
  pond_id        uuid not null references public.ponds (id) on delete cascade,
  metric         text not null,
  status         smallint not null default 0,  -- latest: 0 normal, 1 warning, 2 danger
  alerted_status smallint not null default 0,  -- level last notified; 0 = none outstanding
  normal_since   timestamptz,                  -- when it last became normal
  sms_at         timestamptz,                  -- last text about it
  sms_status     smallint not null default 0,  -- level of that text
  primary key (pond_id, metric)
);
alter table public.pond_alert_state enable row level security;
revoke all on public.pond_alert_state from anon, authenticated;

-- 0 normal, 1 warning, 2 danger; null when there's no value.
-- Same limits as metricBands in lib/models/reading_bands.dart.
create or replace function public.water_reading_status(p_metric text, p_value real)
returns smallint
language sql
immutable
as $$
  select case
    when p_value is null then null
    when p_metric = 'water_temperature' then
      case when p_value < 22 or p_value > 32 then 2
           when p_value < 25 or p_value > 29 then 1 else 0 end
    when p_metric = 'dissolved_oxygen' then
      case when p_value < 2 then 2 when p_value < 4 then 1 else 0 end
    when p_metric = 'ph' then
      case when p_value < 6.0 or p_value > 9.0 then 2
           when p_value < 6.5 or p_value > 8.5 then 1 else 0 end
    when p_metric = 'ammonia' then
      case when p_value > 0.15 then 2 when p_value > 0.05 then 1 else 0 end
  end::smallint
$$;

create or replace function public.evaluate_water_alerts()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_metric   text;
  v_value    real;
  v_status   smallint;
  v_muggy    boolean;
  v_state    pond_alert_state%rowtype;
  v_pond     text;
  v_profile  record;
  v_label    text;
  v_shown    text;
  v_advice   text;
  v_level    text;
  v_title    text;
  v_body     text;
  v_text     boolean;
  v_id       uuid;
  v_url      text;
  v_secret   text;
begin
  if new.pond_id is null or new.user_id is null
     or new.created_at < now() - interval '15 minutes' then
    return new;
  end if;

  select coalesce(nullif(regexp_replace(name, '[^\x20-\x7E]', '', 'g'), ''), 'your pond')
    into v_pond from ponds where id = new.pond_id;
  select phone, phone_verified, alert_sms into v_profile from profiles where id = new.user_id;

  foreach v_metric in array array['dissolved_oxygen', 'water_temperature', 'ph', 'ammonia'] loop
    v_value := case v_metric
      when 'dissolved_oxygen' then new.dissolved_oxygen
      when 'water_temperature' then new.water_temperature
      when 'ph' then new.ph
      else new.ammonia
    end;
    v_status := water_reading_status(v_metric, v_value);
    continue when v_status is null;

    -- Muggy, warm weather: borderline oxygen will fall further tonight.
    v_muggy := v_metric = 'dissolved_oxygen' and v_status = 0 and v_value < 5
               and new.humidity >= 85 and new.water_temperature >= 29;
    if v_muggy then
      v_status := 1;
    end if;

    select * into v_state from pond_alert_state
     where pond_id = new.pond_id and metric = v_metric;
    if not found then
      v_state.pond_id := new.pond_id;
      v_state.metric := v_metric;
      v_state.alerted_status := 0;
      v_state.sms_status := 0;
    end if;
    v_state.status := v_status;

    v_label := case v_metric
      when 'dissolved_oxygen' then 'Dissolved oxygen'
      when 'water_temperature' then 'Water temperature'
      when 'ph' then 'pH'
      else 'Ammonia'
    end;
    -- ASCII only (one SMS segment): "C", not the degree sign.
    v_shown := case v_metric
      when 'dissolved_oxygen' then to_char(v_value, 'FM990.0') || ' mg/L'
      when 'water_temperature' then to_char(v_value, 'FM990.0') || ' C'
      when 'ph' then to_char(v_value, 'FM990.00')
      else to_char(v_value, 'FM990.00') || ' mg/L'
    end;

    if v_status > v_state.alerted_status then
      -- Entered warning, or got worse: notify.
      v_level := case v_status when 2 then 'danger' else 'warning' end;
      v_advice := case
        when v_muggy then
          'Humid, warm weather: it may drop tonight. Run the aerators overnight.'
        when v_metric = 'dissolved_oxygen' then
          'Turn on the aerators now and stop feeding.'
        when v_metric = 'water_temperature' and v_value > 29 then
          'Shade the pond, aerate and feed less.'
        when v_metric = 'water_temperature' then
          'Feed less and avoid cold water changes.'
        when v_metric = 'ph' and v_value < 6.5 then
          'Apply agricultural lime.'
        when v_metric = 'ph' then
          'Change part of the water; do not add lime.'
        else
          'Stop feeding and change part of the water.'
      end;
      v_title := format('%s: %s %s', v_pond, v_label, case v_status when 2 then 'in danger' else 'warning' end);
      v_body := format('%s is %s. %s', v_label, v_shown, v_advice);

      v_text := v_profile.phone is not null and coalesce(v_profile.phone_verified, false)
        and (v_profile.alert_sms = 'warning' or (v_profile.alert_sms = 'critical' and v_status = 2))
        and (v_state.sms_at is null or v_state.sms_at < now() - interval '2 hours'
             or v_status > v_state.sms_status);

      insert into notifications (user_id, pond_id, type, title, body, sms_status)
      values (new.user_id, new.pond_id, 'water_alert_' || v_level, v_title, v_body,
              case when v_text then 'pending' else 'skipped' end)
      returning id into v_id;

      if v_text then
        select decrypted_secret into v_url from vault.decrypted_secrets where name = 'isdasafe_project_url';
        select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'alert_sms_secret';
        if v_url is null or v_secret is null then
          update notifications set sms_status = 'not_configured' where id = v_id;
        else
          perform net.http_post(
            url := rtrim(v_url, '/') || '/functions/v1/send-alert-sms',
            body := jsonb_build_object(
              'notification_id', v_id,
              'message', format('IsdaSafe %s: Pond "%s" %s is %s. %s',
                                upper(v_level), left(v_pond, 30), v_label, v_shown, v_advice)
            ),
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || v_secret
            )
          );
          v_state.sms_at := now();
          v_state.sms_status := v_status;
        end if;
      end if;

      v_state.alerted_status := v_status;
      v_state.normal_since := null;
    elsif v_status = 0 then
      v_state.normal_since := coalesce(v_state.normal_since, new.created_at);
      if v_state.alerted_status > 0 and v_state.normal_since <= now() - interval '30 minutes' then
        insert into notifications (user_id, pond_id, type, title, body, sms_status)
        values (new.user_id, new.pond_id, 'water_alert_cleared',
                format('%s: %s back to normal', v_pond, v_label),
                format('%s is %s again.', v_label, v_shown), 'skipped');
        v_state.alerted_status := 0;
      end if;
    else
      v_state.normal_since := null;
    end if;

    insert into pond_alert_state values (v_state.*)
    on conflict (pond_id, metric) do update set
      status = excluded.status,
      alerted_status = excluded.alerted_status,
      normal_since = excluded.normal_since,
      sms_at = excluded.sms_at,
      sms_status = excluded.sms_status;
  end loop;

  return new;
exception when others then
  -- An alert problem must never lose the reading itself.
  raise warning 'evaluate_water_alerts: %', sqlerrm;
  return new;
end;
$$;

revoke execute on function public.evaluate_water_alerts() from public, anon, authenticated;

drop trigger if exists sensor_readings_water_alerts on public.sensor_readings;
create trigger sensor_readings_water_alerts
  after insert on public.sensor_readings
  for each row execute function public.evaluate_water_alerts();
