-- ===== Amis : table + fonctions (à coller une seule fois dans le SQL Editor de Supabase) =====
create table if not exists public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null references public.profiles(id) on delete cascade,
  addressee uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  constraint friendships_not_self check (requester <> addressee)
);
create unique index if not exists friendships_pair on public.friendships (least(requester, addressee), greatest(requester, addressee));
alter table public.friendships enable row level security;
drop policy if exists friendships_select_own on public.friendships;
create policy friendships_select_own on public.friendships for select to authenticated using (auth.uid() = requester or auth.uid() = addressee);

-- envoyer une demande (ou accepter si l'autre t'avait déjà demandé)
create or replace function public.friend_request(p_username text)
returns text language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); other uuid; f public.friendships;
begin
  if me is null then raise exception 'non connecté'; end if;
  select id into other from public.profiles where lower(username) = lower(trim(p_username)) limit 1;
  if other is null then return 'introuvable'; end if;
  if other = me then return 'soi'; end if;
  select * into f from public.friendships
   where least(requester, addressee) = least(me, other) and greatest(requester, addressee) = greatest(me, other);
  if found then
    if f.status = 'accepted' then return 'deja'; end if;
    if f.addressee = me then update public.friendships set status = 'accepted' where id = f.id; return 'accepte'; end if;
    return 'envoye';
  end if;
  if (select count(*) from public.friendships where requester = me and status = 'pending') >= 30 then return 'limite'; end if;
  insert into public.friendships (requester, addressee) values (me, other);
  return 'envoye';
end $$;

-- accepter / refuser une demande reçue
create or replace function public.friend_respond(p_other uuid, p_accept boolean)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if p_accept then
    update public.friendships set status = 'accepted' where requester = p_other and addressee = auth.uid() and status = 'pending';
  else
    delete from public.friendships where requester = p_other and addressee = auth.uid() and status = 'pending';
  end if;
end $$;

-- retirer un ami / annuler une demande
create or replace function public.friend_remove(p_other uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  delete from public.friendships
   where least(requester, addressee) = least(auth.uid(), p_other) and greatest(requester, addressee) = greatest(auth.uid(), p_other);
end $$;

-- ma liste d'amis et de demandes
create or replace function public.friends_list()
returns table(id uuid, username text, avatar_url text, pr integer, status text, incoming boolean)
language sql security definer set search_path to 'public' stable as $$
  select p.id, p.username, p.avatar_url, p.pr, f.status, (f.addressee = auth.uid() and f.status = 'pending')
  from public.friendships f
  join public.profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
  where auth.uid() in (f.requester, f.addressee)
  order by f.status, p.username;
$$;

revoke all on function public.friend_request(text) from public, anon;
revoke all on function public.friend_respond(uuid, boolean) from public, anon;
revoke all on function public.friend_remove(uuid) from public, anon;
revoke all on function public.friends_list() from public, anon;
grant execute on function public.friend_request(text) to authenticated;
grant execute on function public.friend_respond(uuid, boolean) to authenticated;
grant execute on function public.friend_remove(uuid) to authenticated;
grant execute on function public.friends_list() to authenticated;
