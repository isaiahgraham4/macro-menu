-- Leanrrr food data on Supabase (project "leanrrr", ref dmfmrqvmwvabzkqgdbdw, Sydney).
-- Every food the app ships (restaurant menus per country, everyday foods, USDA survey foods, supermarket foods) is a row
-- in public.foods, grouped by dataset. Anyone can read; only Scripts/supabase/upload.py writes, with the upload key.
-- The app fetches a whole dataset as one JSON in the same layout as the bundled files (public.dataset).
-- Editing a food or chain in the dashboard gives its dataset a new revision and publish time, so phones pick it up.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- One row per file the app bundles: menu-AU (MenuData.json), menu-US (MenuData-US.json) ... generic, survey, supermarket.
create table public.datasets (
  id text primary key check (id ~ '^(menu-[A-Z]{2}|generic|survey|supermarket)$'),
  file text not null,                         -- the bundled file it mirrors
  format int not null default 1,
  country text,
  revision text not null,                     -- fingerprint; changes whenever anything in the dataset does
  published text not null,                    -- ISO 8601 UTC; phones only take a dataset newer than theirs
  updated_at timestamptz not null default now()
);

create table public.chains (
  dataset text not null references public.datasets(id) on delete cascade,
  id text not null,
  position int not null,
  data jsonb not null check (data ? 'id' and data ? 'name'),   -- the chain exactly as in the file
  primary key (dataset, id)
);

create table public.foods (
  dataset text not null references public.datasets(id) on delete cascade,
  id text not null,
  position int not null,                      -- order in the file
  chain text not null,
  name text not null check (length(name) > 0),
  cat text not null,
  kj numeric not null check (kj >= 0),
  cal numeric not null check (cal >= 0),
  p numeric not null check (p >= 0),
  c numeric check (c >= 0),                   -- null when the chain doesn't publish it
  f numeric check (f >= 0),
  serve text not null,
  extra jsonb not null default '{}',          -- everything else: nut, diet, modifiers
  primary key (dataset, id)
);
create index foods_dataset_position on public.foods (dataset, position);
create index foods_name on public.foods using gin (to_tsvector('simple', name));

alter table public.datasets enable row level security;
alter table public.chains enable row level security;
alter table public.foods enable row level security;
create policy "Anyone can read datasets" on public.datasets for select to anon, authenticated using (true);
create policy "Anyone can read chains" on public.chains for select to anon, authenticated using (true);
create policy "Anyone can read foods" on public.foods for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.datasets, public.chains, public.foods from anon, authenticated;

-- A whole dataset in the bundled file's layout: {format, country, revision, published, chains, foods}.
create function public.dataset(id text) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object('format', d.format, 'country', d.country, 'revision', d.revision, 'published', d.published))
    || jsonb_build_object(
      'chains', coalesce((select jsonb_agg(c.data order by c.position) from public.chains c where c.dataset = d.id), '[]'::jsonb),
      'foods', coalesce((select jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object('id', f.id, 'chain', f.chain, 'name', f.name, 'cat', f.cat, 'kj', f.kj, 'cal', f.cal,
                                               'p', f.p, 'c', f.c, 'f', f.f, 'serve', f.serve)) || f.extra
          order by f.position) from public.foods f where f.dataset = d.id), '[]'::jsonb))
  from public.datasets d where d.id = dataset.id
$$;

-- Dashboard edits: a new revision and publish time for each dataset touched. Uploads switch this off and set their own.
create function private.touch_datasets(ids text[]) returns void
language sql security definer set search_path = '' as $$
  update public.datasets set revision = substr(md5(random()::text || clock_timestamp()::text), 1, 16),
    published = to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), updated_at = now()
  where id = any(ids)
$$;
create function private.touch_after_insert() returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('leanrrr.uploading', true), '') <> 'on' then
    perform private.touch_datasets(array(select distinct dataset from new_rows));
  end if;
  return null;
end $$;
create function private.touch_after_delete() returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('leanrrr.uploading', true), '') <> 'on' then
    perform private.touch_datasets(array(select distinct dataset from old_rows));
  end if;
  return null;
end $$;
create function private.touch_after_update() returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('leanrrr.uploading', true), '') <> 'on' then
    perform private.touch_datasets(array(select dataset from new_rows union select dataset from old_rows));
  end if;
  return null;
end $$;
create trigger foods_touch_insert after insert on public.foods referencing new table as new_rows for each statement execute function private.touch_after_insert();
create trigger foods_touch_update after update on public.foods referencing old table as old_rows new table as new_rows for each statement execute function private.touch_after_update();
create trigger foods_touch_delete after delete on public.foods referencing old table as old_rows for each statement execute function private.touch_after_delete();
create trigger chains_touch_insert after insert on public.chains referencing new table as new_rows for each statement execute function private.touch_after_insert();
create trigger chains_touch_update after update on public.chains referencing old table as old_rows new table as new_rows for each statement execute function private.touch_after_update();
create trigger chains_touch_delete after delete on public.chains referencing old table as old_rows for each statement execute function private.touch_after_delete();

-- Uploads. The key is random and lives only in the Mac's keychain ("Leanrrr Supabase upload"); only its SHA-256 is stored here.
-- Rows go to staging in parts (each request stays well inside the 3-second limit), then commit_upload swaps them in at once,
-- so phones never see half a dataset.
create table private.upload_keys (hash text primary key, created_at timestamptz not null default now());
create table private.staging (
  dataset text not null,
  kind text not null check (kind in ('chain', 'food')),
  position int not null,
  data jsonb not null,
  primary key (dataset, kind, position)
);

create function private.check_key(key text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if key is null or not exists (select 1 from private.upload_keys k where k.hash = encode(sha256(convert_to(key, 'UTF8')), 'hex')) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
end $$;

create function public.stage_upload(key text, dataset text, kind text, start int, items jsonb) returns int
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.check_key(stage_upload.key);
  if stage_upload.start = 0 and stage_upload.kind = 'chain' then delete from private.staging s where s.dataset = stage_upload.dataset; end if;
  insert into private.staging (dataset, kind, position, data)
    select stage_upload.dataset, stage_upload.kind, stage_upload.start + (e.n - 1)::int, e.item
    from jsonb_array_elements(stage_upload.items) with ordinality as e(item, n)
  on conflict (dataset, kind, position) do update set data = excluded.data;
  return jsonb_array_length(stage_upload.items);
end $$;

create function public.commit_upload(key text, dataset text, file text, format int, country text, revision text, published text)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare n_chains int; n_foods int;
begin
  perform private.check_key(commit_upload.key);
  select count(*) filter (where kind = 'chain'), count(*) filter (where kind = 'food') into n_chains, n_foods
    from private.staging s where s.dataset = commit_upload.dataset;
  if n_foods = 0 then raise exception 'Nothing staged for %', commit_upload.dataset; end if;
  perform set_config('leanrrr.uploading', 'on', true);
  insert into public.datasets as d (id, file, format, country, revision, published, updated_at)
    values (commit_upload.dataset, commit_upload.file, commit_upload.format, commit_upload.country, commit_upload.revision, commit_upload.published, now())
    on conflict (id) do update set file = excluded.file, format = excluded.format, country = excluded.country,
      revision = excluded.revision, published = excluded.published, updated_at = now();
  delete from public.chains c where c.dataset = commit_upload.dataset;
  delete from public.foods f where f.dataset = commit_upload.dataset;
  insert into public.chains (dataset, id, position, data)
    select s.dataset, s.data->>'id', s.position, s.data from private.staging s
    where s.dataset = commit_upload.dataset and s.kind = 'chain';
  insert into public.foods (dataset, id, position, chain, name, cat, kj, cal, p, c, f, serve, extra)
    select s.dataset, s.data->>'id', s.position, s.data->>'chain', s.data->>'name', s.data->>'cat',
      (s.data->>'kj')::numeric, (s.data->>'cal')::numeric, (s.data->>'p')::numeric, (s.data->>'c')::numeric, (s.data->>'f')::numeric,
      s.data->>'serve', s.data - array['id', 'chain', 'name', 'cat', 'kj', 'cal', 'p', 'c', 'f', 'serve']
    from private.staging s where s.dataset = commit_upload.dataset and s.kind = 'food';
  delete from private.staging s where s.dataset = commit_upload.dataset;
  perform set_config('leanrrr.uploading', 'off', true);
  return jsonb_build_object('dataset', commit_upload.dataset, 'chains', n_chains, 'foods', n_foods, 'revision', commit_upload.revision);
end $$;

revoke execute on function public.stage_upload(text, text, text, int, jsonb), public.commit_upload(text, text, text, int, text, text, text) from public;
grant execute on function public.stage_upload(text, text, text, int, jsonb), public.commit_upload(text, text, text, int, text, text, text) to anon;
revoke execute on all functions in schema private from public, anon, authenticated;
