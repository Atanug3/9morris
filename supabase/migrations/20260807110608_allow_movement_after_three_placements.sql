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
  v_pieces_remaining integer;
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
      if (v_state #>> array['piecesToPlace', v_opponent])::integer = 0
         and (
           (v_state #>> array['piecesOnBoard', v_opponent])::integer < 3
           or not private.morris_has_legal_move(v_state, v_opponent)
         ) then
        v_winner := v_current;
        v_state := jsonb_set(v_state, '{winner}', to_jsonb(v_winner), false);
      else
        v_state := jsonb_set(v_state, '{currentPlayer}', to_jsonb(v_opponent), false);
      end if;
    end if;

  elsif v_action_type = 'move' then
    if (v_state ->> 'removalMode')::boolean then
      raise exception 'A piece cannot be moved now';
    end if;

    v_pieces_remaining := (v_state #>> array['piecesToPlace', v_current])::integer;
    if 9 - v_pieces_remaining < 3 then
      raise exception 'A piece cannot be moved until three pieces have been placed';
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
    if not (v_pieces_remaining = 0 and v_piece_count = 3)
       and not private.morris_are_adjacent(v_from, v_to) then
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
      if (v_state #>> array['piecesToPlace', v_opponent])::integer = 0
         and (
           (v_state #>> array['piecesOnBoard', v_opponent])::integer < 3
           or not private.morris_has_legal_move(v_state, v_opponent)
         ) then
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

    if (v_state #>> array['piecesToPlace', v_opponent])::integer = 0
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