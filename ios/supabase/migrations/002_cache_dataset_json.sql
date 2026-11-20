-- Finished JSON for each dataset, so a read is a lookup rather than rebuilding thousands of foods (which can pass 3 seconds).
create table private.bodies (dataset text primary key references public.datasets(id) on delete cascade, body jsonb not null, built_at timestamptz not null default now());

drop function public.dataset(text);
create function private.build_dataset(ds text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object('format', d.format, 'country', d.country, 'revision', d.revision, 'published', d.published))
    || jsonb_build_object(
      'chains', coalesce((select jsonb_agg(c.data order by c.position) from public.chains c where c.dataset = d.id), '[]'::jsonb),
      'foods', coalesce((select jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object('id', f.id, 'chain', f.chain, 'name', f.name, 'cat', f.cat, 'kj', f.kj, 'cal', f.cal,
                                               'p', f.p, 'c', f.c, 'f', f.f, 'serve', f.serve)) || f.extra
          order by f.position) from public.foods f where f.dataset = d.id), '[]'::jsonb))
  from public.datasets d where d.id = ds
$$;

create function private.rebuild(ids text[]) returns void language sql security definer set search_path = '' as $$
  insert into private.bodies (dataset, body, built_at)
    select d.id, private.build_dataset(d.id), now() from public.datasets d where d.id = any(ids)
  on conflict (dataset) do update set body = excluded.body, built_at = now()
$$;

-- What the app downloads: a whole dataset in the bundled file's layout.
create function public.dataset(id text) returns jsonb language sql stable security definer set search_path = '' as $$
  select b.body from private.bodies b where b.dataset = dataset.id
$$;
grant execute on function public.dataset(text) to anon, authenticated;

-- A dataset's header edited in the dashboard (its date, say) is rebuilt too.
create function private.datasets_changed() returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('leanrrr.uploading', true), '') <> 'on' then
    perform private.rebuild(array(select id from new_rows));
  end if;
  return null;
end $$;
create trigger datasets_rebuild after update on public.datasets referencing new table as new_rows for each statement execute function private.datasets_changed();

-- Uploads build the finished JSON as their last step; that can take a few seconds for the Australian menu.
create or replace function public.commit_upload(key text, dataset text, file text, format int, country text, revision text, published text)
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
  perform private.rebuild(array[commit_upload.dataset]);
  perform set_config('leanrrr.uploading', 'off', true);
  return jsonb_build_object('dataset', commit_upload.dataset, 'chains', n_chains, 'foods', n_foods, 'revision', commit_upload.revision);
end $$;
alter function public.commit_upload(text, text, text, int, text, text, text) set statement_timeout = '60s';
revoke execute on all functions in schema private from public, anon, authenticated;

-- Fill the cache for what's already uploaded.
select private.rebuild(array(select id from public.datasets));
