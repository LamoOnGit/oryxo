-- Oryxo : donner (ou retirer) le passe de combat premium à un joueur
-- À lancer une fois : Supabase -> SQL Editor -> coller tout -> Run.
--
-- Ensuite, dans le SQL Editor :
--   select public.give_pass('Pseudo', true);    -- donner le passe premium
--   select public.give_pass('Pseudo', false);   -- le retirer
--   select username from public.profiles where pass_premium;   -- voir qui l'a

-- 1) la case « passe premium » sur chaque compte (un joueur ne peut pas la cocher lui-même :
--    depuis le jeu, seuls pseudo et avatar sont modifiables, cf. scripts 06 et 08)
alter table public.profiles add column if not exists pass_premium boolean not null default false;
revoke update on public.profiles from anon, authenticated;
grant update (username, avatar_url, updated_at) on public.profiles to authenticated;

-- 2) commande pour Malo (SQL Editor uniquement)
create or replace function public.give_pass(p_username text, p_on boolean default true)
returns text language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.profiles set pass_premium = coalesce(p_on, false) where lower(username) = lower(trim(p_username));
  get diagnostics n = row_count;
  if n = 0 then return 'Aucun joueur avec le pseudo ' || p_username; end if;
  return p_username || case when p_on then ' a maintenant le passe premium' else ' n''a plus le passe premium' end;
end $$;
revoke all on function public.give_pass(text, boolean) from public, anon, authenticated;
grant execute on function public.give_pass(text, boolean) to service_role;
