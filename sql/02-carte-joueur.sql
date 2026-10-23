-- Carte joueur : infos publiques d'un joueur + lien d'amitié avec toi
create or replace function public.player_card(p_id uuid)
returns table(id uuid, username text, avatar_url text, pr integer, games integer, wins integer, kills integer, best_place integer, crown boolean, friend text)
language sql security definer set search_path to 'public' stable as $$
  select p.id, p.username, p.avatar_url, coalesce(p.pr,0)::integer, coalesce(p.games,0)::integer, coalesce(p.wins,0)::integer,
         coalesce(p.kills,0)::integer, p.best_place::integer, coalesce(p.crown,false),
         case when auth.uid() = p.id then 'self'
              when f.status = 'accepted' then 'friend'
              when f.status = 'pending' and f.requester = auth.uid() then 'sent'
              when f.status = 'pending' then 'received'
              else 'none' end
  from public.profiles p
  left join public.friendships f
    on least(f.requester, f.addressee) = least(p.id, auth.uid()) and greatest(f.requester, f.addressee) = greatest(p.id, auth.uid())
  where p.id = p_id;
$$;
grant execute on function public.player_card(uuid) to anon, authenticated;
