-- US packaged foods by barcode, from USDA FoodData Central Branded Foods (public domain). Scripts/usda-barcodes.py builds the
-- rows and uploads them with the same keychain upload key as the datasets. Phones look one barcode up at a time through
-- public.barcode(code); the table itself isn't readable with the publishable key.
create table public.barcodes (
  code text primary key,          -- GTIN/UPC without leading zeros, so UPC-A, EAN-13 and GTIN-14 forms all match
  name text not null,
  brand text,
  serve text not null,            -- as the label prints it: "2/3 cup (55 g)"
  amount numeric not null,        -- the serving in grams or millilitres
  unit text not null check (unit in ('g', 'mL')),
  cal numeric not null, p numeric not null, c numeric, f numeric,
  sat numeric, sugar numeric, fibre numeric, sodium numeric,   -- sodium in mg
  date text                       -- FoodData Central publication date
);
alter table public.barcodes enable row level security;
revoke all on public.barcodes from anon, authenticated;

create table private.barcodes_next (like public.barcodes including all);
create table private.barcodes_meta (id int primary key default 1 check (id = 1), source text, rows int, updated_at timestamptz);

create function public.barcode(code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_strip_nulls(to_jsonb(b)) || jsonb_build_object('source', 'usda')
  from public.barcodes b where b.code = ltrim(regexp_replace(barcode.code, '\D', '', 'g'), '0')
$$;

create function public.stage_barcodes(key text, start int, items jsonb) returns int
language plpgsql security definer set search_path = '' as $$
begin
  perform private.check_key(stage_barcodes.key);
  if stage_barcodes.start = 0 then truncate private.barcodes_next; end if;
  insert into private.barcodes_next
    select * from jsonb_populate_recordset(null::private.barcodes_next, stage_barcodes.items)
  on conflict (code) do nothing;
  return jsonb_array_length(stage_barcodes.items);
end $$;

create function public.commit_barcodes(key text, source text) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '300s' as $$
declare n int;
begin
  perform private.check_key(commit_barcodes.key);
  select count(*) into n from private.barcodes_next;
  if n < 1000 then raise exception 'Only % barcodes staged', n; end if;
  truncate public.barcodes;  -- Supabase refuses DELETE without WHERE; truncate is still all-or-nothing in this transaction
  insert into public.barcodes select * from private.barcodes_next;
  truncate private.barcodes_next;
  insert into private.barcodes_meta (id, source, rows, updated_at) values (1, commit_barcodes.source, n, now())
    on conflict (id) do update set source = excluded.source, rows = excluded.rows, updated_at = excluded.updated_at;
  return jsonb_build_object('barcodes', n, 'source', commit_barcodes.source);
end $$;

revoke execute on function public.barcode(text), public.stage_barcodes(text, int, jsonb), public.commit_barcodes(text, text) from public;
grant execute on function public.barcode(text), public.stage_barcodes(text, int, jsonb), public.commit_barcodes(text, text) to anon, authenticated;
