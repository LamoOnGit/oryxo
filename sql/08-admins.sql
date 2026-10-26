-- Oryxo : admins du jeu (ils ont tous les skins, y compris ceux ajoutés plus tard)
-- À lancer une fois : Supabase -> SQL Editor -> coller tout -> Run.
--
-- Ensuite, dans le SQL Editor :
--   select public.set_admin('Pseudo', true);    -- donner les droits admin
--   select public.set_admin('Pseudo', false);   -- les retirer
--   select username from public.profiles where is_admin;   -- voir les admins

-- 1) la case « admin » sur chaque compte (un joueur ne peut pas la cocher lui-même :
--    depuis le jeu, seuls pseudo et avatar sont modifiables, cf. script 06)
alter table public.profiles add column if not exists is_admin boolean not null default false;
revoke update on public.profiles from anon, authenticated;
grant update (username, avatar_url, updated_at) on public.profiles to authenticated;

-- 2) commande pour Malo (SQL Editor uniquement)
create or replace function public.set_admin(p_username text, p_admin boolean default true)
returns text language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.profiles set is_admin = coalesce(p_admin, false) where lower(username) = lower(trim(p_username));
  get diagnostics n = row_count;
  if n = 0 then return 'Aucun joueur avec le pseudo ' || p_username; end if;
  return p_username || case when p_admin then ' est maintenant admin' else ' n''est plus admin' end;
end $$;
revoke all on function public.set_admin(text, boolean) from public, anon, authenticated;
grant execute on function public.set_admin(text, boolean) to service_role;

-- 3) Malo est admin
select public.set_admin('RaisedByLamo', true);
