create or replace function public.record_ranked_result(p_user uuid, p_mode text, p_placement integer, p_kills integer)
returns table(pr_before integer, pr_delta integer, pr_after integer, rank text)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  prof public.profiles;
  d integer;          -- division : 0 = Rookie I ... 8 = Titan III, 9 = Céleste
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

  d := case when prof.pr >= 1250 then 9 when prof.pr >= 1050 then 8 when prof.pr >= 875 then 7
            when prof.pr >= 700 then 6 when prof.pr >= 550 then 5 when prof.pr >= 425 then 4
            when prof.pr >= 300 then 3 when prof.pr >= 200 then 2 when prof.pr >= 100 then 1 else 0 end;

  place_pts := case when p_placement = 1 then 30 when p_placement = 2 then 20 when p_placement = 3 then 14
                    when p_placement <= 5 then 8 when p_placement <= 8 then 2 else 0 end;

  -- gains de moins en moins forts en montant
  gain := round((place_pts + least(greatest(p_kills, 0), 5) * 2) * (1.0 - d * 0.07));
  -- pertes de plus en plus fortes en montant (le top 3 ne perd jamais)
  loss := case when p_placement <= 3 then 0
               else round((2 + d * 2.5) * (case when p_placement > 8 then 1.5 else 1 end)) end;
  delta := gain - loss;

  streak := case when delta < 0 then prof.loss_streak + 1 else 0 end;
  floor_pr := case when prof.pr >= 1250 then 1250 when prof.pr >= 700 then 700
                   when prof.pr >= 300 then 300 else 0 end;
  newpr := greatest(0, prof.pr + delta);
  -- protection de rang : on ne retombe pas sous Challenger / Titan / Céleste avant 3 défaites d'affilée
  if newpr < floor_pr and streak < 3 then newpr := floor_pr; end if;
  if streak >= 3 then streak := 0; end if;

  update public.profiles set
    pr = newpr, loss_streak = streak,
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
