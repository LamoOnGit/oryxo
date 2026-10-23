-- ===== Oryxo : classé v3 (Céleste I-II-III, Top 500, récompenses, frise, réglages liés au compte) =====
-- À coller une seule fois dans le SQL Editor de Supabase, puis Run.

-- 1) nouvelles colonnes
alter table public.profiles add column if not exists settings jsonb;
alter table public.profiles add column if not exists peak_pr integer not null default 0;
update public.profiles set peak_pr = greatest(coalesce(peak_pr, 0), coalesce(pr, 0));

-- 2) réglages (touches, apparence, récompenses équipées) : chacun ne modifie que les siens
create or replace function public.save_settings(p_settings jsonb)
returns void language sql security definer set search_path to 'public' as $$
  update public.profiles set settings = p_settings
  where id = auth.uid() and p_settings is not null and pg_column_size(p_settings) < 8000;
$$;
revoke all on function public.save_settings(jsonb) from public, anon;
grant execute on function public.save_settings(jsonb) to authenticated;

-- 3) calcul des PR : 12 paliers (Rookie I à Céleste III), meilleur PR retenu pour les récompenses
create or replace function public.record_ranked_result(p_user uuid, p_mode text, p_placement integer, p_kills integer)
returns table(pr_before integer, pr_delta integer, pr_after integer, rank text)
language plpgsql security definer set search_path to 'public' as $function$
declare
  prof public.profiles;
  d integer;
  place_pts integer;
  gain integer;
  loss integer;
  delta integer;
  newpr integer;
  floor_pr integer;
  streak integer;
begin
  select * into prof from public.profiles where id = p_user for update;
  if not found then raise exception 'profil introuvable'; end if;

  d := case when prof.pr >= 1800 then 11 when prof.pr >= 1500 then 10 when prof.pr >= 1250 then 9
            when prof.pr >= 1050 then 8 when prof.pr >= 875 then 7 when prof.pr >= 700 then 6
            when prof.pr >= 550 then 5 when prof.pr >= 425 then 4 when prof.pr >= 300 then 3
            when prof.pr >= 200 then 2 when prof.pr >= 100 then 1 else 0 end;

  place_pts := case when p_placement = 1 then 30 when p_placement = 2 then 20 when p_placement = 3 then 14
                    when p_placement <= 5 then 8 when p_placement <= 8 then 2 else 0 end;
  gain := round((place_pts + least(greatest(p_kills, 0), 5) * 2) * (1.0 - d * 0.07));
  loss := case when p_placement <= 3 then 0
               else round((2 + d * 2.5) * (case when p_placement > 8 then 1.5 else 1 end)) end;
  delta := gain - loss;

  streak := case when delta < 0 then prof.loss_streak + 1 else 0 end;
  floor_pr := case when prof.pr >= 1250 then 1250 when prof.pr >= 700 then 700
                   when prof.pr >= 300 then 300 else 0 end;
  newpr := greatest(0, prof.pr + delta);
  if newpr < floor_pr and streak < 3 then newpr := floor_pr; end if;
  if streak >= 3 then streak := 0; end if;

  update public.profiles set
    pr = newpr, loss_streak = streak, peak_pr = greatest(coalesce(peak_pr, 0), newpr),
    games = games + 1,
    wins = wins + (case when p_placement = 1 then 1 else 0 end),
    kills = kills + greatest(p_kills, 0),
    best_place = least(coalesce(best_place, 99), p_placement),
    crown = (p_placement = 1),
    updated_at = now()
  where id = p_user;

  insert into public.matches (user_id, mode, placement, kills, pr_before, pr_delta, pr_after)
  values (p_user, p_mode, p_placement, greatest(p_kills, 0), prof.pr, newpr - prof.pr, newpr);

  return query select prof.pr, newpr - prof.pr, newpr, public.rank_name(newpr);
end $function$;

-- 4) carte joueur : + meilleur PR, place dans le Top 500, frise de progression, design de carte
drop function if exists public.player_card(uuid);
create function public.player_card(p_id uuid)
returns table(id uuid, username text, avatar_url text, pr integer, games integer, wins integer, kills integer,
              best_place integer, crown boolean, friend text, peak_pr integer, top_pos integer, timeline jsonb, design text)
language sql security definer set search_path to 'public' stable as $$
  select p.id, p.username, p.avatar_url, coalesce(p.pr,0)::integer, coalesce(p.games,0)::integer, coalesce(p.wins,0)::integer,
         coalesce(p.kills,0)::integer, p.best_place::integer, coalesce(p.crown,false),
         case when auth.uid() = p.id then 'self'
              when f.status = 'accepted' then 'friend'
              when f.status = 'pending' and f.requester = auth.uid() then 'sent'
              when f.status = 'pending' then 'received'
              else 'none' end,
         greatest(coalesce(p.peak_pr,0), coalesce(p.pr,0))::integer,
         case when coalesce(p.pr,0) >= 1800 then
           (select case when c.n <= 500 then c.n end from (select 1 + count(*)::integer as n from public.profiles o where o.pr >= 1800 and o.pr > p.pr) c)
         end,
         (select jsonb_agg(jsonb_build_object('min', t.min, 'at', x.at) order by t.min)
            from unnest(array[100,200,300,425,550,700,875,1050,1250,1500,1800]) as t(min)
            cross join lateral (select min(m.created_at) as at from public.matches m where m.user_id = p.id and m.pr_after >= t.min) x
           where x.at is not null),
         p.settings->'look'->>'card'
  from public.profiles p
  left join public.friendships f
    on least(f.requester, f.addressee) = least(p.id, auth.uid()) and greatest(f.requester, f.addressee) = greatest(p.id, auth.uid())
  where p.id = p_id;
$$;
grant execute on function public.player_card(uuid) to anon, authenticated;
