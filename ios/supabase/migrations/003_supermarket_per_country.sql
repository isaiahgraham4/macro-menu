-- Supermarket foods per country: SupermarketFoods-NZ.json and so on (Scripts/supermarket-foods.py) upload as supermarket-NZ, -US,
-- -CA, -GB and -ZA. Australia's stays "supermarket", the id app versions before 1.3 read.
alter table public.datasets drop constraint datasets_id_check;
alter table public.datasets add constraint datasets_id_check check (id ~ '^(menu-[A-Z]{2}|generic|survey|supermarket|supermarket-[A-Z]{2})$');
