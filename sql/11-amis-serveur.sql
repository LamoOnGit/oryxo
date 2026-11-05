-- Oryxo : le serveur (clé secrète = rôle service_role) doit pouvoir lire les amitiés.
-- Sans ça : statut des amis (en ligne / en partie / hors ligne) et invitations en groupe ne marchent pas
-- (https://oryxo.eu/status affichait "friendships 403" code 42501).
-- À lancer une fois : Supabase (projet rexptnaqcumxrdbxhmoi) -> SQL Editor -> coller -> Run.
grant usage on schema public to service_role;
grant select on public.friendships to service_role;
grant select on public.profiles to service_role;
