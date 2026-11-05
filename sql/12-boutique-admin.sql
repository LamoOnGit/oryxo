-- Oryxo : réglages de la boutique gérés depuis le panneau Admin du jeu (pack en vedette, prix, promos, packs cachés,
-- carte de l'Arène, annonce sur l'accueil).
-- À lancer une fois : Supabase (projet rexptnaqcumxrdbxhmoi) -> SQL Editor -> coller tout -> Run. (Il faut avoir lancé 08-admins.sql et 10-oryx.sql avant.)
--
-- Tout le monde peut LIRE les réglages (le jeu en a besoin), seuls les admins (profiles.is_admin) peuvent les MODIFIER.
-- Les prix et les packs cachés sont aussi appliqués au moment de l'achat (buy_with_oryx passe par oryx_price).

create table if not exists public.shop_config (
  id integer primary key default 1 check (id = 1),
  cfg jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into public.shop_config (id, cfg) values (1, '{}'::jsonb) on conflict (id) do nothing;
alter table public.shop_config enable row level security;
revoke all on public.shop_config from anon, authenticated;

-- lire les réglages (joueurs connectés ou non)
create or replace function public.get_shop_config() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select cfg from public.shop_config where id = 1), '{}'::jsonb)
$$;

-- enregistrer les réglages (admins seulement)
create or replace function public.set_shop_config(p_cfg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not coalesce((select is_admin from public.profiles where id = auth.uid()), false) then
    return jsonb_build_object('ok', false, 'err', 'admin');
  end if;
  if jsonb_typeof(p_cfg) <> 'object' or length(p_cfg::text) > 20000 then
    return jsonb_build_object('ok', false, 'err', 'format');
  end if;
  update public.shop_config set cfg = p_cfg, updated_at = now(), updated_by = auth.uid() where id = 1;
  return jsonb_build_object('ok', true);
end $$;

-- prix en Oryx : prix de base, remplacé par le prix ou la promo du panneau Admin ; pack caché = plus en vente
create or replace function public.oryx_price(p_item integer) returns integer
language plpgsql stable security definer set search_path = public as $$
declare base integer; it jsonb; pr integer; promo integer;
begin
  base := case p_item
    when 60 then 500 when 61 then 500 when 63 then 500 when 64 then 500   -- packs mythiques
    when 90 then 450                                                        -- passe premium (saison 1)
    else null end;
  if base is null then return null; end if;
  it := (select cfg -> 'items' -> p_item::text from public.shop_config where id = 1);
  if it is null then return base; end if;
  if coalesce((it ->> 'hidden')::boolean, false) then return null; end if;
  pr := nullif(it ->> 'price', '')::integer;
  if pr is not null and pr > 0 then base := pr; end if;
  promo := nullif(it ->> 'promo', '')::integer;
  if promo is not null and promo > 0 and promo < base
     and (nullif(it ->> 'promoUntil', '') is null or (it ->> 'promoUntil')::timestamptz > now()) then
    base := promo;
  end if;
  return base;
end $$;

revoke all on function public.get_shop_config(), public.set_shop_config(jsonb) from public, anon, authenticated;
grant execute on function public.get_shop_config() to anon, authenticated;
grant execute on function public.set_shop_config(jsonb) to authenticated;
