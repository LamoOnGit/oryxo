-- Oryxo : réparation du classement global
-- 1) supprime toutes les anciennes versions des fonctions (même avec d'autres paramètres)
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.proname in ('leaderboard', 'leaderboard_position')
  loop
    execute 'drop function ' || r.sig || ' cascade';
  end loop;
end $$;

-- 2) colonnes utilisées (ajoutées seulement si elles manquent)
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists crown boolean default false;

-- 3) top N joueurs par PR
create function public.leaderboard(n integer default 10)
returns table (id uuid, username text, pr integer, avatar_url text, crown boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.username::text, coalesce(p.pr, 0)::integer, p.avatar_url::text, coalesce(p.crown, false)::boolean
  from public.profiles p
  where p.username is not null
  order by p.pr desc nulls last, p.username
  limit greatest(1, least(coalesce(n, 10), 100));
$$;

-- 4) position d'un joueur
create function public.leaderboard_position(p_user uuid)
returns integer
language sql stable security definer set search_path = public as $$
  select (count(*) + 1)::integer
  from public.profiles o, public.profiles me
  where me.id = p_user and o.username is not null and coalesce(o.pr, 0) > coalesce(me.pr, 0);
$$;

grant execute on function public.leaderboard(integer) to anon, authenticated;
grant execute on function public.leaderboard_position(uuid) to anon, authenticated;

-- 5) test : doit afficher une liste de joueurs
select * from public.leaderboard(10);
