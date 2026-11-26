-- Suggestions sent from Settings → Suggestions. Phones can only add one through public.suggest(); nobody can read them with the
-- publishable key. Read them in the dashboard (Table Editor → private → suggestions) or the SQL editor.
-- No account, device id or email is stored: only what the person typed, what kind of suggestion it is, the app version and
-- which country's menus they use.
create table private.suggestions (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind text not null check (kind in ('restaurant', 'feature', 'fix', 'other')),
  body text not null check (char_length(body) between 3 and 1000),
  app_version text check (char_length(app_version) <= 20),
  country text check (char_length(country) <= 4),
  done boolean not null default false   -- tick when it's been dealt with
);

create function public.suggest(kind text, body text, app_version text default null, country text default null) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  -- A flood guard for the free plan: at most 500 suggestions a day from everyone together.
  if (select count(*) from private.suggestions where created_at > now() - interval '1 day') >= 500 then
    raise exception 'Too many suggestions today';
  end if;
  insert into private.suggestions (kind, body, app_version, country)
    values (suggest.kind, btrim(suggest.body), left(suggest.app_version, 20), left(suggest.country, 4));
  return true;
end $$;

revoke execute on function public.suggest(text, text, text, text) from public;
grant execute on function public.suggest(text, text, text, text) to anon, authenticated;
