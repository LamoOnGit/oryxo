-- Oryxo : système de bannissement
-- À lancer une fois dans Supabase -> SQL Editor -> Run.
--
-- Ensuite, pour bannir ou débannir, toujours dans le SQL Editor :
--   select public.ban('Pseudo', '7 days', 'Triche');      -- 7 jours  (aussi : '2 hours', '30 days'…)
--   select public.ban('Pseudo', null, 'Insultes');        -- définitif
--   select public.unban('Pseudo');                        -- lever le ban
--   select username, banned_until, ban_reason from public.profiles where banned_until > now();   -- voir les bannis

-- 1) colonnes
alter table public.profiles add column if not exists banned_until timestamptz;
alter table public.profiles add column if not exists ban_reason text;

-- 2) sécurité : depuis le jeu, un joueur ne peut modifier QUE son pseudo et son avatar.
--    (sinon un tricheur pourrait changer ses PR, sa couronne… ou lever son propre ban)
revoke update on public.profiles from anon, authenticated;
grant update (username, avatar_url, updated_at) on public.profiles to authenticated;

-- 3) commandes pour Malo (utilisables seulement depuis le SQL Editor / le serveur, jamais depuis le jeu)
create or replace function public.ban(p_username text, p_duration interval, p_reason text default null)
returns text language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.profiles
     set banned_until = case when p_duration is null then 'infinity'::timestamptz else now() + p_duration end,
         ban_reason = nullif(trim(coalesce(p_reason, '')), '')
   where lower(username) = lower(trim(p_username));
  get diagnostics n = row_count;
  if n = 0 then return 'Aucun joueur avec le pseudo ' || p_username; end if;
  return p_username || ' est banni ' || case when p_duration is null then 'définitivement' else 'pour ' || p_duration::text end;
end $$;

create or replace function public.unban(p_username text)
returns text language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.profiles set banned_until = null, ban_reason = null where lower(username) = lower(trim(p_username));
  get diagnostics n = row_count;
  if n = 0 then return 'Aucun joueur avec le pseudo ' || p_username; end if;
  return p_username || ' n''est plus banni';
end $$;

revoke all on function public.ban(text, interval, text) from public, anon, authenticated;
revoke all on function public.unban(text) from public, anon, authenticated;
grant execute on function public.ban(text, interval, text) to service_role;
grant execute on function public.unban(text) to service_role;
