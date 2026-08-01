create extension if not exists pgcrypto;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  player1 uuid not null references auth.users(id) on delete cascade,
  player2 uuid references auth.users(id) on delete set null,
  player1_name text not null,
  player2_name text,
  status text not null default 'waiting'
    check (status in ('waiting', 'active', 'finished', 'abandoned')),
  game_state jsonb not null,
  revision integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.games enable row level security;

drop policy if exists "Participants can view their games" on public.games;
create policy "Participants can view their games"
on public.games
for select
to authenticated
using (auth.uid() = player1 or auth.uid() = player2);

create or replace function public.create_game(
  p_initial_state jsonb,
  p_display_name text
)
returns setof public.games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if jsonb_typeof(p_initial_state -> 'board') <> 'array'
     or jsonb_array_length(p_initial_state -> 'board') <> 24 then
    raise exception 'Invalid initial game state';
  end if;

  loop
    v_room_code := upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));
    begin
      return query
      insert into public.games (
        room_code,
        player1,
        player1_name,
        game_state
      )
      values (
        v_room_code,
        auth.uid(),
        left(coalesce(nullif(trim(p_display_name), ''), 'Player 1'), 40),
        p_initial_state
      )
      returning *;
      return;
    exception
      when unique_violation then
        null;
    end;
  end loop;
end;
$$;

create or replace function public.join_game(
  p_room_code text,
  p_display_name text
)
returns setof public.games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1
    from public.games
    where room_code = upper(trim(p_room_code))
      and player1 = auth.uid()
  ) then
    raise exception 'You cannot join your own room as Player 2';
  end if;

  return query
  update public.games
  set player2 = auth.uid(),
      player2_name = left(coalesce(nullif(trim(p_display_name), ''), 'Player 2'), 40),
      status = 'active',
      updated_at = now()
  where room_code = upper(trim(p_room_code))
    and status = 'waiting'
    and player2 is null
  returning *;

  if not found then
    raise exception 'Room not found or already full';
  end if;
end;
$$;

create or replace function public.submit_game_state(
  p_game_id uuid,
  p_expected_revision integer,
  p_game_state jsonb,
  p_status text
)
returns setof public.games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games%rowtype;
  v_expected_user uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_game
  from public.games
  where id = p_game_id
  for update;

  if not found then
    raise exception 'Game not found';
  end if;

  if v_game.status <> 'active' then
    raise exception 'Game is not active';
  end if;

  if v_game.revision <> p_expected_revision then
    raise exception 'Game state has changed; refresh and try again';
  end if;

  v_expected_user := case
    when v_game.game_state ->> 'currentPlayer' = 'P1' then v_game.player1
    else v_game.player2
  end;

  if auth.uid() <> v_expected_user then
    raise exception 'It is not your turn';
  end if;

  if jsonb_typeof(p_game_state -> 'board') <> 'array'
     or jsonb_array_length(p_game_state -> 'board') <> 24
     or p_game_state ->> 'currentPlayer' not in ('P1', 'P2')
     or p_game_state ->> 'phase' not in ('placement', 'movement') then
    raise exception 'Invalid game state';
  end if;

  return query
  update public.games
  set game_state = p_game_state,
      status = case when p_status = 'finished' then 'finished' else 'active' end,
      revision = revision + 1,
      updated_at = now()
  where id = p_game_id
  returning *;
end;
$$;

create or replace function public.leave_game(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.games
  set status = 'abandoned',
      updated_at = now()
  where id = p_game_id
    and status in ('waiting', 'active')
    and (player1 = auth.uid() or player2 = auth.uid());
end;
$$;

revoke all on public.games from anon, authenticated;
grant select on public.games to authenticated;

revoke all on function public.create_game(jsonb, text) from public;
revoke all on function public.join_game(text, text) from public;
revoke all on function public.submit_game_state(uuid, integer, jsonb, text) from public;
revoke all on function public.leave_game(uuid) from public;

grant execute on function public.create_game(jsonb, text) to authenticated;
grant execute on function public.join_game(text, text) to authenticated;
grant execute on function public.submit_game_state(uuid, integer, jsonb, text) to authenticated;
grant execute on function public.leave_game(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'games'
  ) then
    alter publication supabase_realtime add table public.games;
  end if;
end;
$$;
