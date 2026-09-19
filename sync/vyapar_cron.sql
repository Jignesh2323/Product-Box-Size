-- Daily Vyapar → Product Box Size stock sync, as it actually runs.
--
-- This lives in the SOURCE project (begblflwhxbbipsmxytd), not in the app's
-- own project — the app project has no admin access from here, so the sync
-- pushes outward over PostgREST instead of being pulled in.
--
-- Leg 1 (Vyapar → vyapar_items) already lands around 04:45 UTC on its own.
-- Leg 2 is this file: cron at 05:30 UTC, 45 minutes of buffer behind it.
--
-- Applied 19 Sep 2026, after the previous cloud routine stopped on 15 Sep
-- and went unnoticed for three days. Kept here so the job is reviewable and
-- rebuildable; the database is not the only copy.

create extension if not exists http with schema extensions;

create table if not exists public.pbs_push_log (
  id           bigint generated always as identity primary key,
  ran_at       timestamptz not null default now(),
  rows_pushed  integer not null,
  live         integer not null,
  gone         integer not null
);

comment on table public.pbs_push_log is
  'Product Box Size app ko bheje gaye Vyapar stock ka record. Fail hui run yahan nahi dikhti -- wo cron.job_run_details me hoti hai.';

alter table public.pbs_push_log enable row level security;
revoke all on table public.pbs_push_log from anon;
revoke all on table public.pbs_push_log from authenticated;

create or replace function public.push_vyapar_to_box_app()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  app_url  constant text := 'https://genlxypyehcpxatcsiut.supabase.co/rest/v1/pbs_vyapar_items';
  -- Publishable key -- wahi jo index.html me ship hoti hai, likhne ki ijazat RLS deti hai.
  app_key  constant text := 'sb_publishable_pxE-irYl9twtYkk2UDi38g_NWkaW4jP';
  batch_n  constant int  := 200;
  run_at   timestamptz := now();
  run_ts   text;
  hdrs     http_header[];
  batch    jsonb;
  resp     http_response;
  cur_off  int := 0;
  total    int;
  live     int;
  gone     int := 0;
  has_src  boolean;
begin
  perform http_set_curlopt('CURLOPT_TIMEOUT_MS', '30000');
  run_ts := to_char(run_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');

  select count(*), count(*) filter (where is_active)
    into total, live
    from public.vyapar_items;

  -- Chhota dump = kuch gadbad hai. Aadha data bhejne se accha kuch na bhejo.
  if total < 100 then
    raise exception 'vyapar_items me sirf % rows -- itna chhota galat lagta hai, kuch push nahi kiya', total;
  end if;

  hdrs := array[
    http_header('apikey', app_key),
    http_header('Authorization', 'Bearer ' || app_key)
  ];

  -- source_at column app me hai ya nahi, ek baar poochh lete hain. Na ho to
  -- uske bina bhejte hain -- ek nayi column ke chakkar me roz ki sync nahi rukni chahiye.
  select * into resp from http((
    'get', app_url || '?select=source_at&limit=1', hdrs, null, null)::http_request);
  has_src := resp.status between 200 and 299;

  loop
    -- live stock = coalesce(override, current_stock) -- override hi wo figure hai jo Vyapar khud dikhata hai
    -- source_at = us item ka apna last_stock_update, yaani Vyapar ke numbers kitne taaza hain.
    -- synced_at alag cheez hai: app ko data kab mila. Dono isliye ki pipeline ka
    -- kaunsa hissa ruka hai wo pata chale.
    select jsonb_agg(
             jsonb_build_object(
               'item_name',     t.item_name,
               'current_stock', coalesce(t.stock_quantity_override, t.current_stock),
               'is_active',     t.is_active,
               'synced_at',     run_ts)
             || case when has_src
                     then jsonb_build_object('source_at', t.last_stock_update at time zone 'utc')
                     else '{}'::jsonb end)
      into batch
      from (select * from public.vyapar_items
             order by item_name
             offset cur_off limit batch_n) t;

    exit when batch is null;

    select * into resp from http((
      'post', app_url,
      hdrs || http_header('Prefer', 'resolution=merge-duplicates,return=minimal'),
      'application/json', batch::text)::http_request);

    if resp.status < 200 or resp.status > 299 then
      raise exception 'upsert fail (offset %): HTTP % -- %',
        cur_off, resp.status, left(coalesce(resp.content, ''), 300);
    end if;

    cur_off := cur_off + batch_n;
  end loop;

  -- Jis row ko is run ne chhua hi nahi, wo Vyapar se gaayab hai -> ab live nahi.
  -- Discontinue flags app ke apne hain, unhe yahan se koi haath nahi lagata.
  select * into resp from http((
    'patch',
    app_url || '?is_active=eq.true&synced_at=lt.' || run_ts,
    hdrs || http_header('Prefer', 'return=representation'),
    'application/json',
    jsonb_build_object('is_active', false, 'synced_at', run_ts)::text)::http_request);

  if resp.status < 200 or resp.status > 299 then
    raise exception 'gaayab items mark karne me fail: HTTP % -- %',
      resp.status, left(coalesce(resp.content, ''), 300);
  end if;

  gone := coalesce(jsonb_array_length(resp.content::jsonb), 0);

  insert into public.pbs_push_log (ran_at, rows_pushed, live, gone)
       values (run_at, total, live, gone);

  return format('pushed %s rows | live %s | ab live nahi %s | source_at %s',
                total, live, gone, case when has_src then 'bheja' else 'column nahi hai, chhoda' end);
end;
$fn$;

comment on function public.push_vyapar_to_box_app() is
  'vyapar_items ka stock Product Box Size app ke Supabase me bhejta hai. Roz cron se chalta hai.';

revoke all on function public.push_vyapar_to_box_app() from public;
revoke all on function public.push_vyapar_to_box_app() from anon;
revoke all on function public.push_vyapar_to_box_app() from authenticated;

-- 05:30 UTC = 11:00 AM IST. Server UTC pe chalta hai.
select cron.schedule('push_vyapar_to_box_app', '30 5 * * *',
                     'select public.push_vyapar_to_box_app()');

-- Haal dekhne ke liye:
--   select * from public.pbs_push_log order by ran_at desc limit 10;
--   select * from cron.job_run_details where jobid =
--     (select jobid from cron.job where jobname = 'push_vyapar_to_box_app')
--     order by start_time desc limit 10;
