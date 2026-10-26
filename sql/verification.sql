-- Oryxo : vérifie que les scripts Supabase 01 à 07 sont bien installés.
-- Supabase -> SQL Editor -> colle tout -> Run. Chaque ligne doit afficher ✅.
select script, element,
       case when ok then '✅ OK' else '❌ MANQUANT (relance le script ' || script || ')' end as etat
from (values
  ('01', 'table des amis (friendships)',            to_regclass('public.friendships') is not null),
  ('01', 'fonction friend_request',                 to_regprocedure('public.friend_request(text)') is not null),
  ('01', 'fonction friends_list',                   to_regprocedure('public.friends_list()') is not null),
  ('02', 'fonction player_card (carte joueur)',     to_regprocedure('public.player_card(uuid)') is not null),
  ('03', 'fonction record_ranked_result (PR)',      exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'record_ranked_result')),
  ('04', 'colonne profiles.settings',               exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'settings')),
  ('04', 'colonne profiles.peak_pr',                exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'peak_pr')),
  ('04', 'fonction save_settings',                  to_regprocedure('public.save_settings(jsonb)') is not null),
  ('05', 'colonne profiles.avatar_url',             exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'avatar_url')),
  ('05', 'colonne profiles.crown',                  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'crown')),
  ('05', 'fonction leaderboard (classement)',       to_regprocedure('public.leaderboard(integer)') is not null),
  ('05', 'fonction leaderboard_position',           to_regprocedure('public.leaderboard_position(uuid)') is not null),
  ('06', 'colonne profiles.banned_until',           exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'banned_until')),
  ('06', 'colonne profiles.ban_reason',             exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'ban_reason')),
  ('06', 'fonction ban',                            to_regprocedure('public.ban(text,interval,text)') is not null),
  ('06', 'fonction unban',                          to_regprocedure('public.unban(text)') is not null),
  ('06', 'un joueur ne peut plus changer ses PR',   not has_column_privilege('authenticated', 'public.profiles', 'pr', 'UPDATE')),
  ('06', 'un joueur peut changer son pseudo',       has_column_privilege('authenticated', 'public.profiles', 'username', 'UPDATE')),
  ('07', 'table des clans',                         to_regclass('public.clans') is not null and to_regclass('public.clan_members') is not null),
  ('07', 'fonctions des clans',                     to_regprocedure('public.clan_get(uuid)') is not null and to_regprocedure('public.clan_create(text,text,text,text,text,text)') is not null and to_regprocedure('public.clan_leave()') is not null),
  ('07', 'quêtes sauvegardées avec le compte',      to_regprocedure('public.quest_sync(jsonb)') is not null),
  ('07', 'clan et badges sur la carte joueur',      to_regprocedure('public.player_extras(uuid)') is not null)
) as t(script, element, ok)
order by script, element;
