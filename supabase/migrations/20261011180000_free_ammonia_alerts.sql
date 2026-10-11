-- Water alerts judge ammonia as FREE ammonia (un-ionised NH3), the part
-- that's toxic to fish, instead of the sensor's total ammonia nitrogen --
-- like the app's pond status (MetricType.water, lib/models/metric_type.dart).
--
-- free_ammonia() works it out from total ammonia, pH and water temperature
-- the same way as lib/models/free_ammonia.dart (Emerson et al. 1975, as NH3),
-- so it doesn't depend on the device sending its own value. Limits are
-- metricBands[MetricType.freeAmmonia]: warning above 0.02, danger above 0.05.

-- Free NH3 in mg/L from total ammonia nitrogen (mg/L), pH and water
-- temperature (C); null if any is missing.
create or replace function public.free_ammonia(p_total real, p_ph real, p_temp real)
returns real
language sql
immutable
as $$
  select (p_total
          / (power(10::double precision, 0.09018 + 2729.92 / (p_temp + 273.15) - p_ph) + 1)
          * (17.031 / 14.007))::real
$$;

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
    when p_metric = 'free_ammonia' then
      case when p_value > 0.05 then 2 when p_value > 0.02 then 1 else 0 end
  end::smallint
$$;

-- Total ammonia no longer alerts; forget where it stood.
delete from public.pond_alert_state where metric = 'ammonia';

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

  foreach v_metric in array array['dissolved_oxygen', 'water_temperature', 'ph', 'free_ammonia'] loop
    v_value := case v_metric
      when 'dissolved_oxygen' then new.dissolved_oxygen
      when 'water_temperature' then new.water_temperature
      when 'ph' then new.ph
      else free_ammonia(new.ammonia, new.ph, new.water_temperature)
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
      else 'Free ammonia'
    end;
    -- ASCII only (one SMS segment): "C", not the degree sign.
    v_shown := case v_metric
      when 'dissolved_oxygen' then to_char(v_value, 'FM990.0') || ' mg/L'
      when 'water_temperature' then to_char(v_value, 'FM990.0') || ' C'
      when 'ph' then to_char(v_value, 'FM990.00')
      else to_char(v_value, 'FM990.000') || ' mg/L'
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
          'Stop feeding, change part of the water and aerate.'
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
