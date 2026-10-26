-- Oryxo : clans (+ sauvegarde des quêtes avec le compte, extras de la carte joueur)
-- À lancer UNE fois : Supabase -> SQL Editor -> coller tout -> Run (l'alerte « destructive » est normale).
-- Règles : 1 clan max par joueur, 30 membres max, rôles Chef / Officier / Membre.
--   Chef : tout (modifier, dissoudre, promouvoir, nommer un autre chef, exclure).
--   Officier : inviter, accepter les demandes, exclure des membres.
-- Les tables ne sont lisibles / modifiables QUE par les fonctions ci-dessous (aucun accès direct depuis le jeu).

-- ============ 1) tables ============
create table if not exists public.clans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tag text not null,
  color text not null default '#4dabf7',
  icon text not null default 'shield',
  description text not null default '',
  policy text not null default 'open' check (policy in ('open', 'request', 'closed')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists clans_name_uniq on public.clans (lower(name));
create unique index if not exists clans_tag_uniq on public.clans (upper(tag));

create table if not exists public.clan_members (
  user_id uuid primary key references public.profiles(id) on delete cascade,   -- 1 clan max par joueur
  clan_id uuid not null references public.clans(id) on delete cascade,
  role text not null default 'member' check (role in ('leader', 'officer', 'member')),
  joined_at timestamptz not null default now()
);
create index if not exists clan_members_clan on public.clan_members (clan_id);

create table if not exists public.clan_requests (     -- demandes pour rejoindre (clans « sur demande »)
  clan_id uuid not null references public.clans(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (clan_id, user_id)
);
create table if not exists public.clan_invites (      -- invitations envoyées par le chef / un officier
  clan_id uuid not null references public.clans(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (clan_id, user_id)
);

alter table public.clans enable row level security;
alter table public.clan_members enable row level security;
alter table public.clan_requests enable row level security;
alter table public.clan_invites enable row level security;
revoke all on public.clans, public.clan_members, public.clan_requests, public.clan_invites from anon, authenticated;

-- progression des quêtes liée au compte
alter table public.profiles add column if not exists quests jsonb not null default '{}'::jsonb;

-- ============ 2) petites aides internes ============
create or replace function public._clan_of(p_user uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select clan_id from public.clan_members where user_id = p_user
$$;
create or replace function public._clan_role(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.clan_members where user_id = p_user
$$;
create or replace function public._clan_count(p_clan uuid) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from public.clan_members where clan_id = p_clan
$$;
-- liste résumée des clans (recherche, invitations, classement)
create or replace function public._clan_row(c public.clans) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'tag', c.tag, 'color', c.color, 'icon', c.icon, 'policy', c.policy,
    'member_count', (select count(*) from public.clan_members m where m.clan_id = c.id),
    'total_pr', (select coalesce(sum(p.pr), 0) from public.clan_members m join public.profiles p on p.id = m.user_id where m.clan_id = c.id))
$$;
revoke all on function public._clan_of(uuid), public._clan_role(uuid), public._clan_count(uuid), public._clan_row(public.clans) from public, anon, authenticated;

-- ============ 3) lecture ============
-- mon clan (p_clan = null) ou un clan précis
create or replace function public.clan_get(p_clan uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cid uuid := coalesce(p_clan, public._clan_of(auth.uid())); c public.clans; me_role text; tot integer; res jsonb;
begin
  if cid is null then return null; end if;
  select * into c from public.clans where id = cid;
  if not found then return null; end if;
  me_role := (select role from public.clan_members where user_id = auth.uid() and clan_id = cid);
  select coalesce(sum(p.pr), 0) into tot from public.clan_members m join public.profiles p on p.id = m.user_id where m.clan_id = cid;
  res := jsonb_build_object(
    'id', c.id, 'name', c.name, 'tag', c.tag, 'color', c.color, 'icon', c.icon, 'description', c.description, 'policy', c.policy,
    'member_count', public._clan_count(cid), 'total_pr', tot, 'my_role', me_role,
    'rank', 1 + (select count(*) from (select m.clan_id, sum(p.pr) s from public.clan_members m join public.profiles p on p.id = m.user_id group by m.clan_id) x where x.s > tot),
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'pr', p.pr, 'avatar_url', p.avatar_url, 'role', m.role) order by m.joined_at)
                         from public.clan_members m join public.profiles p on p.id = m.user_id where m.clan_id = cid), '[]'::jsonb),
    'requests', case when me_role in ('leader', 'officer') then coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'pr', p.pr, 'avatar_url', p.avatar_url) order by r.created_at)
                         from public.clan_requests r join public.profiles p on p.id = r.user_id where r.clan_id = cid), '[]'::jsonb) else '[]'::jsonb end);
  return res;
end $$;

-- recherche (vide = classement des clans par PR total)
create or replace function public.clan_search(p_q text default '') returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by (r->>'total_pr')::int desc, r->>'name'), '[]'::jsonb) from (
    select r from (
      select public._clan_row(c) r from public.clans c
      where coalesce(trim(p_q), '') = '' or c.name ilike '%' || trim(p_q) || '%' or c.tag ilike trim(p_q) || '%') a
    order by (r->>'total_pr')::int desc, r->>'name'
    limit 50) t
$$;

create or replace function public.clan_my_invites() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public._clan_row(c) order by i.created_at desc), '[]'::jsonb)
  from public.clan_invites i join public.clans c on c.id = i.clan_id where i.user_id = auth.uid()
$$;

-- tags de clan d'une liste de joueurs (affichés devant les pseudos)
create or replace function public.clan_tags(p_ids uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id, 'tag', c.tag, 'color', c.color)), '[]'::jsonb)
  from public.clan_members m join public.clans c on c.id = m.clan_id
  where m.user_id = any (p_ids[1:200])
$$;

-- ============ 4) actions (renvoient un code lu par le jeu) ============
create or replace function public.clan_create(p_name text, p_tag text, p_color text, p_icon text, p_desc text, p_policy text) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text := trim(coalesce(p_name, '')); t text := upper(trim(coalesce(p_tag, ''))); cid uuid;
begin
  if uid is null then return 'forbidden'; end if;
  if public._clan_of(uid) is not null then return 'in_clan'; end if;
  if char_length(n) < 3 or char_length(n) > 24 then return 'bad_name'; end if;
  if t !~ '^[A-Z0-9]{2,5}$' then return 'bad_tag'; end if;
  if exists (select 1 from public.clans where lower(name) = lower(n)) then return 'name_taken'; end if;
  if exists (select 1 from public.clans where upper(tag) = t) then return 'tag_taken'; end if;
  insert into public.clans (name, tag, color, icon, description, policy, created_by)
  values (n, t,
          case when p_color ~* '^#[0-9a-f]{6}$' then lower(p_color) else '#4dabf7' end,
          case when p_icon in ('shield', 'flame', 'star', 'crown', 'bolt', 'skull', 'sword', 'planet') then p_icon else 'shield' end,
          left(trim(coalesce(p_desc, '')), 200),
          case when p_policy in ('open', 'request', 'closed') then p_policy else 'open' end, uid)
  returning id into cid;
  insert into public.clan_members (user_id, clan_id, role) values (uid, cid, 'leader');
  delete from public.clan_requests where user_id = uid;
  delete from public.clan_invites where user_id = uid;
  return 'ok';
exception when unique_violation then return 'name_taken';
end $$;

create or replace function public.clan_update(p_desc text, p_color text, p_icon text, p_policy text) returns text
language plpgsql security definer set search_path = public as $$
declare cid uuid := public._clan_of(auth.uid());
begin
  if cid is null or public._clan_role(auth.uid()) <> 'leader' then return 'forbidden'; end if;
  update public.clans set
    description = left(trim(coalesce(p_desc, '')), 200),
    color = case when p_color ~* '^#[0-9a-f]{6}$' then lower(p_color) else color end,
    icon = case when p_icon in ('shield', 'flame', 'star', 'crown', 'bolt', 'skull', 'sword', 'planet') then p_icon else icon end,
    policy = case when p_policy in ('open', 'request', 'closed') then p_policy else policy end
  where id = cid;
  return 'ok';
end $$;

create or replace function public.clan_disband() returns text
language plpgsql security definer set search_path = public as $$
declare cid uuid := public._clan_of(auth.uid());
begin
  if cid is null or public._clan_role(auth.uid()) <> 'leader' then return 'forbidden'; end if;
  delete from public.clans where id = cid;   -- membres, demandes et invitations partent avec
  return 'disbanded';
end $$;

create or replace function public.clan_join(p_clan uuid) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c public.clans;
begin
  if uid is null then return 'forbidden'; end if;
  if public._clan_of(uid) is not null then return 'in_clan'; end if;
  select * into c from public.clans where id = p_clan for update;
  if not found then return 'not_found'; end if;
  if public._clan_count(c.id) >= 30 then return 'full'; end if;
  if c.policy = 'open' or exists (select 1 from public.clan_invites where clan_id = c.id and user_id = uid) then
    insert into public.clan_members (user_id, clan_id, role) values (uid, c.id, 'member');
    delete from public.clan_requests where user_id = uid;
    delete from public.clan_invites where user_id = uid;
    return 'joined';
  end if;
  if c.policy = 'closed' then return 'closed'; end if;
  insert into public.clan_requests (clan_id, user_id) values (c.id, uid) on conflict do nothing;
  return 'requested';
end $$;

create or replace function public.clan_invite(p_username text) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cid uuid := public._clan_of(uid); target uuid;
begin
  if cid is null or public._clan_role(uid) not in ('leader', 'officer') then return 'forbidden'; end if;
  select id into target from public.profiles where lower(username) = lower(trim(coalesce(p_username, ''))) limit 1;
  if target is null then return 'introuvable'; end if;
  if public._clan_of(target) is not null then return 'deja'; end if;
  if public._clan_count(cid) >= 30 then return 'full'; end if;
  if exists (select 1 from public.clan_invites where clan_id = cid and user_id = target) then return 'already'; end if;
  insert into public.clan_invites (clan_id, user_id, invited_by) values (cid, target, uid);
  return 'invited';
end $$;

create or replace function public.clan_invite_respond(p_clan uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if not exists (select 1 from public.clan_invites where clan_id = p_clan and user_id = uid) then return 'not_found'; end if;
  if not p_accept then delete from public.clan_invites where clan_id = p_clan and user_id = uid; return 'ok'; end if;
  if public._clan_of(uid) is not null then return 'in_clan'; end if;
  perform 1 from public.clans where id = p_clan for update;
  if public._clan_count(p_clan) >= 30 then return 'full'; end if;
  insert into public.clan_members (user_id, clan_id, role) values (uid, p_clan, 'member');
  delete from public.clan_requests where user_id = uid;
  delete from public.clan_invites where user_id = uid;
  return 'joined';
end $$;

-- chef / officier : accepter ou refuser une demande
create or replace function public.clan_respond(p_user uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cid uuid := public._clan_of(uid);
begin
  if cid is null or public._clan_role(uid) not in ('leader', 'officer') then return 'forbidden'; end if;
  if not exists (select 1 from public.clan_requests where clan_id = cid and user_id = p_user) then return 'not_found'; end if;
  delete from public.clan_requests where clan_id = cid and user_id = p_user;
  if not p_accept then return 'ok'; end if;
  if public._clan_of(p_user) is not null then return 'deja'; end if;
  perform 1 from public.clans where id = cid for update;
  if public._clan_count(cid) >= 30 then return 'full'; end if;
  insert into public.clan_members (user_id, clan_id, role) values (p_user, cid, 'member');
  delete from public.clan_requests where user_id = p_user;
  delete from public.clan_invites where user_id = p_user;
  return 'ok';
end $$;

create or replace function public.clan_kick(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cid uuid := public._clan_of(uid); me_role text := public._clan_role(uid); t_role text;
begin
  if cid is null or p_user = uid then return 'forbidden'; end if;
  select role into t_role from public.clan_members where user_id = p_user and clan_id = cid;
  if t_role is null then return 'not_found'; end if;
  if not (me_role = 'leader' and t_role <> 'leader' or me_role = 'officer' and t_role = 'member') then return 'forbidden'; end if;
  delete from public.clan_members where user_id = p_user and clan_id = cid;
  return 'ok';
end $$;

-- chef seulement : promouvoir / rétrograder / nommer un nouveau chef (l'ancien devient officier)
create or replace function public.clan_set_role(p_user uuid, p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cid uuid := public._clan_of(uid);
begin
  if cid is null or public._clan_role(uid) <> 'leader' or p_user = uid then return 'forbidden'; end if;
  if p_role not in ('leader', 'officer', 'member') then return 'forbidden'; end if;
  if not exists (select 1 from public.clan_members where user_id = p_user and clan_id = cid) then return 'not_found'; end if;
  if p_role = 'leader' then
    update public.clan_members set role = 'officer' where user_id = uid;
  end if;
  update public.clan_members set role = p_role where user_id = p_user and clan_id = cid;
  return 'ok';
end $$;

-- quitter : le chef qui part passe la main (officier le plus ancien, sinon membre le plus ancien) ; dernier membre = clan supprimé
create or replace function public.clan_leave() returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cid uuid := public._clan_of(uid); was text := public._clan_role(uid); heir uuid;
begin
  if cid is null then return 'not_found'; end if;
  delete from public.clan_members where user_id = uid;
  if public._clan_count(cid) = 0 then delete from public.clans where id = cid; return 'left'; end if;
  if was = 'leader' then
    select user_id into heir from public.clan_members where clan_id = cid order by (role = 'officer') desc, joined_at limit 1;
    update public.clan_members set role = 'leader' where user_id = heir;
  end if;
  return 'left';
end $$;

-- ============ 5) quêtes liées au compte + extras de la carte joueur ============
create or replace function public.quest_get() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(quests, '{}'::jsonb) from public.profiles where id = auth.uid()
$$;

-- fusionne la progression envoyée par le jeu (on garde toujours la valeur la plus haute)
create or replace function public.quest_sync(p_progress jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cur jsonb; k text; val text; merged jsonb;
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  select coalesce(quests, '{}'::jsonb) into cur from public.profiles where id = auth.uid();
  merged := coalesce(cur, '{}'::jsonb);
  if jsonb_typeof(p_progress) = 'object' then
    for k, val in select key, value::text from jsonb_each(p_progress) limit 64 loop
      if k ~ '^[a-z_]{2,24}$' and val ~ '^[0-9]{1,7}$' then
        merged := merged || jsonb_build_object(k, greatest(coalesce((merged->>k)::bigint, 0), val::bigint));
      end if;
    end loop;
  end if;
  update public.profiles set quests = merged where id = auth.uid();
  return merged;
end $$;

-- ce que la carte joueur affiche en plus : badges, stats des quêtes, clan
create or replace function public.player_extras(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'progress', coalesce(p.quests, '{}'::jsonb),
    'stats', jsonb_build_object('wins', coalesce(p.wins, 0), 'games', coalesce(p.games, 0), 'pr', coalesce(p.pr, 0),
      'friends', (select count(*) from public.friendships f where f.status = 'accepted' and (f.requester = p.id or f.addressee = p.id)),
      'clan', case when m.clan_id is null then 0 else 1 end),
    'clan', case when c.id is null then null else jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'color', c.color, 'icon', c.icon) end)
  from public.profiles p
  left join public.clan_members m on m.user_id = p.id
  left join public.clans c on c.id = m.clan_id
  where p.id = p_id
$$;

-- ============ 6) droits ============
do $$
declare f text;
begin
  foreach f in array array[
    'clan_get(uuid)', 'clan_search(text)', 'clan_my_invites()', 'clan_tags(uuid[])', 'clan_create(text,text,text,text,text,text)',
    'clan_update(text,text,text,text)', 'clan_disband()', 'clan_join(uuid)', 'clan_invite(text)', 'clan_invite_respond(uuid,boolean)',
    'clan_respond(uuid,boolean)', 'clan_kick(uuid)', 'clan_set_role(uuid,text)', 'clan_leave()', 'quest_get()', 'quest_sync(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated';
  end loop;
end $$;
revoke all on function public.player_extras(uuid) from public;
grant execute on function public.player_extras(uuid) to anon, authenticated;
