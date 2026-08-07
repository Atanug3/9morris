create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

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
  v_initial_state jsonb := jsonb_build_object(
    'board', to_jsonb(array_fill(null::text, array[24])),
    'currentPlayer', 'P1',
    'phase', 'placement',
    'piecesToPlace', '{"P1":9,"P2":9}'::jsonb,
    'piecesOnBoard', '{"P1":0,"P2":0}'::jsonb,
    'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
    'removalMode', false,
    'winner', null
  );
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  loop
    v_room_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
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
        v_initial_state
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

create or replace function private.morris_other_player(p_player text)
returns text
language sql
immutable
strict
as $$
  select case p_player when 'P1' then 'P2' else 'P1' end;
$$;

create or replace function private.morris_is_valid_position(p_position integer)
returns boolean
language sql
immutable
as $$
  select p_position between 0 and 23;
$$;

create or replace function private.morris_are_adjacent(p_from integer, p_to integer)
returns boolean
language sql
immutable
strict
as $$
  select exists (
    select 1
    from (
      values
        (0, 1), (1, 2), (0, 9), (2, 14), (9, 21), (14, 23), (21, 22), (22, 23),
        (3, 4), (4, 5), (3, 10), (5, 13), (10, 18), (13, 20), (18, 19), (19, 20),
        (6, 7), (7, 8), (6, 11), (8, 12), (11, 15), (12, 17), (15, 16), (16, 17),
        (1, 4), (4, 7), (9, 10), (10, 11), (12, 13), (13, 14), (16, 19), (19, 22)
    ) as edge(a, b)
    where (edge.a = p_from and edge.b = p_to)
       or (edge.a = p_to and edge.b = p_from)
  );
$$;

create or replace function private.morris_is_mill(
  p_board jsonb,
  p_position integer,
  p_player text
)
returns boolean
language sql
immutable
strict
as $$
  select exists (
    select 1
    from (
      values
        (0, 1, 2), (3, 4, 5), (6, 7, 8),
        (15, 16, 17), (18, 19, 20), (21, 22, 23),
        (0, 9, 21), (3, 10, 18), (6, 11, 15),
        (1, 4, 7), (16, 19, 22),
        (8, 12, 17), (5, 13, 20), (2, 14, 23),
        (9, 10, 11), (12, 13, 14)
    ) as mill(a, b, c)
    where p_position in (mill.a, mill.b, mill.c)
      and p_board ->> mill.a = p_player
      and p_board ->> mill.b = p_player
      and p_board ->> mill.c = p_player
  );
$$;

create or replace function private.morris_all_pieces_in_mills(
  p_board jsonb,
  p_player text
)
returns boolean
language sql
immutable
strict
as $$
  select not exists (
    select 1
    from generate_series(0, 23) as position
    where p_board ->> position = p_player
      and not private.morris_is_mill(p_board, position, p_player)
  );
$$;

create or replace function private.morris_exceeds_repetition(
  p_history jsonb,
  p_from integer,
  p_to integer
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_length integer := jsonb_array_length(coalesce(p_history, '[]'::jsonb));
  v_first jsonb;
  v_second jsonb;
  v_third jsonb;
  v_fourth jsonb;
begin
  if v_length < 4 then
    return false;
  end if;

  v_first := p_history -> (v_length - 4);
  v_second := p_history -> (v_length - 3);
  v_third := p_history -> (v_length - 2);
  v_fourth := p_history -> (v_length - 1);

  return (v_first ->> 'from')::integer = p_from
    and (v_first ->> 'to')::integer = p_to
    and (v_second ->> 'from')::integer = p_to
    and (v_second ->> 'to')::integer = p_from
    and (v_third ->> 'from')::integer = p_from
    and (v_third ->> 'to')::integer = p_to
    and (v_fourth ->> 'from')::integer = p_to
    and (v_fourth ->> 'to')::integer = p_from;
end;
$$;

create or replace function private.morris_has_legal_move(
  p_state jsonb,
  p_player text
)
returns boolean
language plpgsql
immutable
strict
as $$
declare
  v_board jsonb := p_state -> 'board';
  v_history jsonb := coalesce(p_state #> array['moveHistory', p_player], '[]'::jsonb);
  v_piece_count integer := (p_state #>> array['piecesOnBoard', p_player])::integer;
  v_from integer;
  v_to integer;
begin
  for v_from in 0..23 loop
    if v_board ->> v_from <> p_player then
      continue;
    end if;

    for v_to in 0..23 loop
      if v_board -> v_to <> 'null'::jsonb then
        continue;
      end if;

      if v_piece_count <> 3 and not private.morris_are_adjacent(v_from, v_to) then
        continue;
      end if;

      if not private.morris_exceeds_repetition(v_history, v_from, v_to) then
        return true;
      end if;
    end loop;
  end loop;

  return false;
end;
$$;

create or replace function public.submit_game_action(
  p_game_id uuid,
  p_expected_revision integer,
  p_action jsonb
)
returns setof public.games
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_game public.games%rowtype;
  v_state jsonb;
  v_board jsonb;
  v_action_type text := p_action ->> 'type';
  v_current text;
  v_opponent text;
  v_expected_user uuid;
  v_position integer;
  v_from integer;
  v_to integer;
  v_piece_count integer;
  v_history jsonb;
  v_winner text;
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

  v_state := v_game.game_state;
  v_board := v_state -> 'board';
  v_current := v_state ->> 'currentPlayer';
  v_opponent := private.morris_other_player(v_current);
  v_expected_user := case when v_current = 'P1' then v_game.player1 else v_game.player2 end;

  if auth.uid() <> v_expected_user then
    raise exception 'It is not your turn';
  end if;

  if v_state ->> 'winner' is not null then
    raise exception 'Game has already finished';
  end if;

  if jsonb_typeof(v_board) <> 'array' or jsonb_array_length(v_board) <> 24 then
    raise exception 'Stored game state is invalid';
  end if;

  if v_action_type = 'place' then
    if v_state ->> 'phase' <> 'placement' or (v_state ->> 'removalMode')::boolean then
      raise exception 'A piece cannot be placed now';
    end if;

    v_position := (p_action ->> 'position')::integer;
    if v_position is null or not private.morris_is_valid_position(v_position) then
      raise exception 'Invalid board position';
    end if;
    if v_board -> v_position <> 'null'::jsonb then
      raise exception 'That position is occupied';
    end if;
    if (v_state #>> array['piecesToPlace', v_current])::integer <= 0 then
      raise exception 'No pieces remain to place';
    end if;

    v_board := jsonb_set(v_board, array[v_position::text], to_jsonb(v_current), false);
    v_state := jsonb_set(v_state, '{board}', v_board, false);
    v_state := jsonb_set(
      v_state,
      array['piecesToPlace', v_current],
      to_jsonb((v_state #>> array['piecesToPlace', v_current])::integer - 1),
      false
    );
    v_state := jsonb_set(
      v_state,
      array['piecesOnBoard', v_current],
      to_jsonb((v_state #>> array['piecesOnBoard', v_current])::integer + 1),
      false
    );

    if private.morris_is_mill(v_board, v_position, v_current) then
      v_state := jsonb_set(v_state, '{removalMode}', 'true'::jsonb, false);
    else
      v_state := jsonb_set(v_state, '{currentPlayer}', to_jsonb(v_opponent), false);
    end if;

  elsif v_action_type = 'move' then
    if v_state ->> 'phase' <> 'movement' or (v_state ->> 'removalMode')::boolean then
      raise exception 'A piece cannot be moved now';
    end if;

    v_from := (p_action ->> 'from')::integer;
    v_to := (p_action ->> 'to')::integer;
    if v_from is null
       or v_to is null
       or not private.morris_is_valid_position(v_from)
       or not private.morris_is_valid_position(v_to)
       or v_from = v_to then
      raise exception 'Invalid move positions';
    end if;
    if v_board ->> v_from <> v_current then
      raise exception 'The source piece does not belong to you';
    end if;
    if v_board -> v_to <> 'null'::jsonb then
      raise exception 'The destination is occupied';
    end if;

    v_piece_count := (v_state #>> array['piecesOnBoard', v_current])::integer;
    if v_piece_count <> 3 and not private.morris_are_adjacent(v_from, v_to) then
      raise exception 'The destination is not adjacent';
    end if;

    v_history := coalesce(v_state #> array['moveHistory', v_current], '[]'::jsonb);
    if private.morris_exceeds_repetition(v_history, v_from, v_to) then
      raise exception 'The same piece cannot move back and forth more than twice';
    end if;

    v_board := jsonb_set(v_board, array[v_from::text], 'null'::jsonb, false);
    v_board := jsonb_set(v_board, array[v_to::text], to_jsonb(v_current), false);
    v_history := v_history || jsonb_build_array(
      jsonb_build_object('from', v_from, 'to', v_to)
    );
    if jsonb_array_length(v_history) > 4 then
      v_history := v_history - 0;
    end if;

    v_state := jsonb_set(v_state, '{board}', v_board, false);
    v_state := jsonb_set(v_state, array['moveHistory', v_current], v_history, false);

    if private.morris_is_mill(v_board, v_to, v_current) then
      v_state := jsonb_set(v_state, '{removalMode}', 'true'::jsonb, false);
    else
      if (v_state #>> array['piecesOnBoard', v_opponent])::integer < 3
         or not private.morris_has_legal_move(v_state, v_opponent) then
        v_winner := v_current;
        v_state := jsonb_set(v_state, '{winner}', to_jsonb(v_winner), false);
      else
        v_state := jsonb_set(v_state, '{currentPlayer}', to_jsonb(v_opponent), false);
      end if;
    end if;

  elsif v_action_type = 'remove' then
    if not (v_state ->> 'removalMode')::boolean then
      raise exception 'No piece can be removed now';
    end if;

    v_position := (p_action ->> 'position')::integer;
    if v_position is null or not private.morris_is_valid_position(v_position) then
      raise exception 'Invalid board position';
    end if;
    if v_board ->> v_position <> v_opponent then
      raise exception 'You must remove an opponent piece';
    end if;
    if private.morris_is_mill(v_board, v_position, v_opponent)
       and not private.morris_all_pieces_in_mills(v_board, v_opponent) then
      raise exception 'A piece in a mill cannot be removed while another piece is available';
    end if;

    v_board := jsonb_set(v_board, array[v_position::text], 'null'::jsonb, false);
    v_state := jsonb_set(v_state, '{board}', v_board, false);
    v_state := jsonb_set(
      v_state,
      array['piecesOnBoard', v_opponent],
      to_jsonb((v_state #>> array['piecesOnBoard', v_opponent])::integer - 1),
      false
    );
    v_state := jsonb_set(v_state, '{removalMode}', 'false'::jsonb, false);

    if (v_state #>> '{piecesToPlace,P1}')::integer = 0
       and (v_state #>> '{piecesToPlace,P2}')::integer = 0 then
      v_state := jsonb_set(v_state, '{phase}', '"movement"'::jsonb, false);
    else
      v_state := jsonb_set(v_state, '{phase}', '"placement"'::jsonb, false);
    end if;

    if v_state ->> 'phase' = 'movement'
       and (
         (v_state #>> array['piecesOnBoard', v_opponent])::integer < 3
         or not private.morris_has_legal_move(v_state, v_opponent)
       ) then
      v_winner := v_current;
      v_state := jsonb_set(v_state, '{winner}', to_jsonb(v_winner), false);
    else
      v_state := jsonb_set(v_state, '{currentPlayer}', to_jsonb(v_opponent), false);
    end if;

  else
    raise exception 'Unknown game action';
  end if;

  if v_action_type <> 'remove'
     and not (v_state ->> 'removalMode')::boolean
     and (v_state #>> '{piecesToPlace,P1}')::integer = 0
     and (v_state #>> '{piecesToPlace,P2}')::integer = 0 then
    v_state := jsonb_set(v_state, '{phase}', '"movement"'::jsonb, false);

    if v_action_type = 'place'
       and (
         (v_state #>> array['piecesOnBoard', v_opponent])::integer < 3
         or not private.morris_has_legal_move(v_state, v_opponent)
       ) then
      v_state := jsonb_set(v_state, '{winner}', to_jsonb(v_current), false);
    end if;
  end if;

  return query
  update public.games
  set game_state = v_state,
      status = case when v_state ->> 'winner' is not null then 'finished' else 'active' end,
      revision = revision + 1,
      updated_at = now()
  where id = p_game_id
  returning *;
end;
$$;

revoke all on function public.submit_game_action(uuid, integer, jsonb) from public;
grant execute on function public.submit_game_action(uuid, integer, jsonb) to authenticated;

-- Keep the legacy RPC available until every deployed client uses submit_game_action.
-- Remove it in a separate migration after the client rollout is verified.