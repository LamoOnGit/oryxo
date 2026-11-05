-- Oryxo : les Oryx (gemmes). On achète des Oryx avec de l'argent (Stripe), puis on dépense les Oryx en jeu.
-- À lancer une fois : Supabase -> SQL Editor -> coller tout -> Run. (Il faut avoir lancé 09-passe.sql avant.)
--
-- Commandes pour Malo (SQL Editor) :
--   select public.give_oryx('Pseudo', 500);     -- donner 500 Oryx (nombre négatif = en retirer)
--   select username, oryx from public.profiles order by oryx desc limit 20;   -- les plus gros soldes
--
-- Pour le webhook Stripe (clé service_role) : après un paiement réussi d'une offre d'Oryx,
--   select public.credit_oryx('<uuid du joueur>', 1200, '<id de la session Stripe>');
-- (le même id de session ne crédite jamais deux fois)

-- 1) le solde (un joueur ne peut pas le modifier : depuis le jeu, seuls pseudo et avatar sont modifiables)
alter table public.profiles add column if not exists oryx integer not null default 0 check (oryx >= 0);
revoke update on public.profiles from anon, authenticated;
grant update (username, avatar_url, updated_at) on public.profiles to authenticated;

-- 2) ce qui a été acheté avec des Oryx, et l'historique des Oryx reçus
create table if not exists public.oryx_items (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_id integer not null,
  price integer not null,
  bought_at timestamptz not null default now(),
  primary key (user_id, item_id)
);
create table if not exists public.oryx_credits (
  ref text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null,
  at timestamptz not null default now()
);
alter table public.oryx_items enable row level security;
alter table public.oryx_credits enable row level security;
revoke all on public.oryx_items, public.oryx_credits from anon, authenticated;

-- 3) prix en Oryx (les mêmes que dans le jeu, OX_ORYX_PRICE)
create or replace function public.oryx_price(p_item integer) returns integer
language sql immutable as $$
  select case p_item
    when 60 then 500 when 61 then 500 when 63 then 500 when 64 then 500   -- packs mythiques
    when 90 then 450                                                        -- passe premium (saison 1)
    else null end
$$;

-- 4) acheter avec des Oryx (appelé par le jeu) : vérifie le solde, retire les Oryx, donne l'objet
create or replace function public.buy_with_oryx(p_item integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare price integer; bal integer;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'err', 'auth'); end if;
  price := public.oryx_price(p_item);
  if price is null then return jsonb_build_object('ok', false, 'err', 'item'); end if;
  if exists (select 1 from public.oryx_items where user_id = auth.uid() and item_id = p_item) then
    return jsonb_build_object('ok', false, 'err', 'owned');
  end if;
  select oryx into bal from public.profiles where id = auth.uid() for update;
  if coalesce(bal, 0) < price then return jsonb_build_object('ok', false, 'err', 'poor', 'oryx', coalesce(bal, 0), 'price', price); end if;
  update public.profiles set oryx = oryx - price where id = auth.uid() returning oryx into bal;
  insert into public.oryx_items(user_id, item_id, price) values (auth.uid(), p_item, price);
  if p_item = 90 then update public.profiles set pass_premium = true where id = auth.uid(); end if;
  return jsonb_build_object('ok', true, 'oryx', bal);
end $$;

-- 5) ce que le joueur possède (acheté en Oryx) + son solde
create or replace function public.my_oryx() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'oryx', coalesce((select oryx from public.profiles where id = auth.uid()), 0),
    'items', coalesce((select jsonb_agg(item_id) from public.oryx_items where user_id = auth.uid()), '[]'::jsonb))
$$;

-- 6) créditer des Oryx après un paiement Stripe (webhook, service_role uniquement), sans jamais créditer deux fois
create or replace function public.credit_oryx(p_user uuid, p_amount integer, p_ref text) returns integer
language plpgsql security definer set search_path = public as $$
declare bal integer;
begin
  insert into public.oryx_credits(ref, user_id, amount) values (p_ref, p_user, p_amount) on conflict (ref) do nothing;
  if not found then select oryx into bal from public.profiles where id = p_user; return bal; end if;
  update public.profiles set oryx = greatest(0, oryx + p_amount) where id = p_user returning oryx into bal;
  return bal;
end $$;

-- 7) donner / retirer des Oryx à la main (SQL Editor uniquement)
create or replace function public.give_oryx(p_username text, p_amount integer) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid; bal integer;
begin
  select id into uid from public.profiles where lower(username) = lower(trim(p_username));
  if uid is null then return 'Aucun joueur avec le pseudo ' || p_username; end if;
  bal := public.credit_oryx(uid, p_amount, 'manuel-' || gen_random_uuid());
  return p_username || ' a maintenant ' || bal || ' Oryx';
end $$;

revoke all on function public.buy_with_oryx(integer), public.my_oryx(), public.credit_oryx(uuid, integer, text), public.give_oryx(text, integer) from public, anon, authenticated;
grant execute on function public.buy_with_oryx(integer), public.my_oryx() to authenticated;
grant execute on function public.credit_oryx(uuid, integer, text), public.give_oryx(text, integer) to service_role;
