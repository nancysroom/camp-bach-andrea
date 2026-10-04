-- Camp Bach: ejecutar en SQL Editor del proyecto camp-bach-andrea.
begin;
-- CAMP BACH · realtime party game
-- Run this once in Supabase > SQL Editor.
-- This schema is intentionally simple for a private party room-code game.

create extension if not exists pgcrypto;

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_player_id uuid,
  status text not null default 'lobby',
  game_state jsonb not null default '{"phase":"lobby"}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  name text not null,
  answers jsonb not null default '{}'::jsonb,
  suggestions jsonb not null default '[]'::jsonb,
  ready boolean not null default false,
  score integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  round_no integer not null,
  player_id uuid not null references public.players(id) on delete cascade,
  answer text not null,
  response_ms integer not null default 0,
  created_at timestamptz not null default now(),
  unique (room_id, round_no, player_id)
);

create index if not exists players_room_idx on public.players(room_id);
create index if not exists votes_room_idx on public.votes(room_id);

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.votes enable row level security;


alter table public.rooms add column if not exists owner_id uuid references auth.users(id);
alter table public.players add column if not exists user_id uuid references auth.users(id);
create unique index if not exists players_room_user_idx on public.players(room_id,user_id);
create schema if not exists camp_private;
revoke all on schema camp_private from public;
grant usage on schema camp_private to authenticated;
create or replace function camp_private.member(rid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.players where room_id=rid and user_id=auth.uid());
$$;
create or replace function camp_private.host(rid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.rooms where id=rid and owner_id=auth.uid());
$$;
revoke all on function camp_private.member(uuid),camp_private.host(uuid) from public;
grant execute on function camp_private.member(uuid),camp_private.host(uuid) to authenticated;
-- Replace only the old party policies and this setup's own policies.
do $$ declare pol record; begin
 for pol in select schemaname,tablename,policyname from pg_policies
 where schemaname='public' and tablename in ('rooms','players','votes')
 and (policyname like 'party %' or policyname like 'camp %') loop
 execute format('drop policy %I on %I.%I',pol.policyname,pol.schemaname,pol.tablename);
 end loop;
end $$;
revoke all on public.rooms,public.players,public.votes from anon,authenticated;
grant select on public.rooms,public.players,public.votes to authenticated;
grant update(status,game_state) on public.rooms to authenticated;
grant update(name,answers,suggestions,ready,score) on public.players to authenticated;
grant insert,update on public.votes to authenticated;
create policy "camp read rooms" on public.rooms for select to authenticated using(camp_private.member(id));
create policy "camp host room" on public.rooms for update to authenticated using(camp_private.host(id)) with check(camp_private.host(id));
create policy "camp read players" on public.players for select to authenticated using(camp_private.member(room_id));
create policy "camp update players" on public.players for update to authenticated
 using(user_id=auth.uid() or camp_private.host(room_id)) with check(user_id=auth.uid() or camp_private.host(room_id));
create policy "camp read votes" on public.votes for select to authenticated using(camp_private.member(room_id));
create policy "camp insert votes" on public.votes for insert to authenticated with check(
 exists(select 1 from public.players p where p.id=player_id and p.room_id=votes.room_id and p.user_id=auth.uid()));
create policy "camp update votes" on public.votes for update to authenticated using(
 exists(select 1 from public.players p where p.id=player_id and p.room_id=votes.room_id and p.user_id=auth.uid())) with check(
 exists(select 1 from public.players p where p.id=player_id and p.room_id=votes.room_id and p.user_id=auth.uid()));

create or replace function public.camp_enter_room(player_name text, room_code text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.rooms; p public.players; uid uuid := auth.uid(); n text := trim(player_name); attempts int := 0;
begin
 if uid is null then raise exception 'Inicia sesión para jugar.'; end if;
 if n is null or length(n)<1 or length(n)>40 then raise exception 'Escribe un nombre de 1 a 40 letras.'; end if;
 if room_code is null then
   if (select count(*) from public.rooms where owner_id=uid and created_at>now()-interval '1 day')>=10 then
     raise exception 'Ya creaste suficientes salas hoy.';
   end if;
   loop
     begin
       insert into public.rooms(code,owner_id) values ((10000+floor(random()*90000))::int::text,uid) returning * into r;
       exit;
     exception when unique_violation then
       attempts:=attempts+1; if attempts>=10 then raise exception 'Intenta crear la sala de nuevo.'; end if;
     end;
   end loop;
 else
   select * into r from public.rooms where code=trim(room_code) for update;
   if not found then raise exception 'No existe ese código.'; end if;
   select * into p from public.players where room_id=r.id and user_id=uid;
   if found then return jsonb_build_object('room',to_jsonb(r),'player',to_jsonb(p)); end if;
   if r.status<>'lobby' then raise exception 'La partida ya empezó.'; end if;
   if (select count(*) from public.players where room_id=r.id)>=30 then raise exception 'La sala está llena.'; end if;
   if exists(select 1 from public.players where room_id=r.id and lower(name)=lower(n)) then raise exception 'Ese nombre ya está en la sala.'; end if;
 end if;
 insert into public.players(room_id,user_id,name) values(r.id,uid,n) returning * into p;
 if room_code is null then update public.rooms set host_player_id=p.id where id=r.id returning * into r; end if;
 return jsonb_build_object('room',to_jsonb(r),'player',to_jsonb(p));
end $$;
revoke all on function public.camp_enter_room(text,text) from public,anon;
grant execute on function public.camp_enter_room(text,text) to authenticated;
do $$ declare t text; begin
 foreach t in array array['rooms','players','votes'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
 execute format('alter publication supabase_realtime add table public.%I',t);
 end if; end loop;
end $$;
commit;
