begin;

create extension if not exists pgtap with schema extensions;
select plan(35);

insert into auth.users (
  id, email, aud, role, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'p1-test@example.test',
    'authenticated',
    'authenticated',
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'p2-test@example.test',
    'authenticated',
    'authenticated',
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'outsider-test@example.test',
    'authenticated',
    'authenticated',
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

insert into public.games (
  id, room_code, player1, player2, player1_name, player2_name, status, game_state
)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'TEST01',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Player 1',
  'Player 2',
  'active',
  jsonb_build_object(
    'board', to_jsonb(array_fill(null::text, array[24])),
    'currentPlayer', 'P1',
    'phase', 'placement',
    'piecesToPlace', '{"P1":9,"P2":9}'::jsonb,
    'piecesOnBoard', '{"P1":0,"P2":0}'::jsonb,
    'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
    'removalMode', false,
    'winner', null
  )
);

select ok(
  to_regprocedure('public.submit_game_action(uuid,integer,jsonb)') is not null,
  'authoritative action function exists'
);
select ok(
  to_regprocedure('public.submit_game_state(uuid,integer,jsonb,text)') is not null,
  'legacy whole-state function remains available during client rollout'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.submit_game_state(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'authenticated clients can use the legacy function during rollout'
);
select ok(
  not has_table_privilege('authenticated', 'public.games', 'UPDATE'),
  'authenticated users cannot update game rows directly'
);
select ok(
  not has_table_privilege('anon', 'public.games', 'SELECT'),
  'anonymous users cannot read games'
);
select ok(
  not has_schema_privilege('authenticated', 'private', 'USAGE'),
  'authenticated users cannot call private rule helpers'
);

select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
select lives_ok(
  $$select * from public.create_game(
    '{"board":["P2"],"winner":"P1"}',
    '<img src=x onerror=alert(1)>'
  )$$,
  'an authenticated user can create a game'
);
select is(
  (
    select jsonb_array_length(game_state -> 'board')
    from public.games
    where player1 = '11111111-1111-1111-1111-111111111111'
      and id <> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ),
  24,
  'game creation uses the canonical 24-position board'
);
select is(
  (
    select game_state ->> 'winner'
    from public.games
    where player1 = '11111111-1111-1111-1111-111111111111'
      and id <> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ),
  null,
  'client-supplied initial winner state is ignored'
);
select is(
  (
    select player1_name
    from public.games
    where player1 = '11111111-1111-1111-1111-111111111111'
      and id <> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ),
  '<img src=x onerror=alert(1)>',
  'display names are stored as text for safe textContent rendering'
);
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 0,
    '{"type":"place","position":0}'
  )$$,
  'Player 1 can make a legal placement'
);
select is(
  (select game_state ->> 'currentPlayer' from public.games
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'P2',
  'a legal placement advances the turn'
);
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1,
    '{"type":"place","position":1}'
  )$$,
  'P0001',
  'It is not your turn',
  'the same user cannot move twice'
);

select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  true
);
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1,
    '{"type":"place","position":3}'
  )$$,
  'Player 2 can place'
);
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 2,
    '{"type":"place","position":1}'
  )$$,
  'Player 1 can build toward a mill'
);
select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  true
);
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 3,
    '{"type":"place","position":4}'
  )$$,
  'Player 2 can make the next placement'
);
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 4,
    '{"type":"place","position":2}'
  )$$,
  'Player 1 can complete a mill'
);
select ok(
  (select (game_state ->> 'removalMode')::boolean from public.games
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'a completed mill enters removal mode'
);

select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  true
);
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 5,
    '{"type":"remove","position":0}'
  )$$,
  'P0001',
  'It is not your turn',
  'the opponent cannot perform the mill removal'
);
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 5,
    '{"type":"remove","position":3}'
  )$$,
  'the mill owner can remove a valid opponent piece'
);

update public.games
set revision = 10,
    status = 'active',
    game_state = jsonb_build_object(
      'board',
      '["P1",null,"P2","P1",null,"P2","P1",null,"P2","P1",null,null,null,null,"P2",null,null,null,null,null,null,null,null,null]'::jsonb,
      'currentPlayer', 'P1',
      'phase', 'movement',
      'piecesToPlace', '{"P1":0,"P2":0}'::jsonb,
      'piecesOnBoard', '{"P1":4,"P2":4}'::jsonb,
      'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
      'removalMode', false,
      'winner', null
    )
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 10,
    '{"type":"move","from":0,"to":23}'
  )$$,
  'P0001',
  'The destination is not adjacent',
  'non-adjacent movement is rejected'
);

update public.games
set revision = 20,
    game_state = jsonb_build_object(
      'board',
      '["P1",null,"P2","P1",null,"P2","P1",null,"P2",null,null,null,null,null,"P2",null,null,null,null,null,null,null,null,null]'::jsonb,
      'currentPlayer', 'P1',
      'phase', 'movement',
      'piecesToPlace', '{"P1":0,"P2":0}'::jsonb,
      'piecesOnBoard', '{"P1":3,"P2":4}'::jsonb,
      'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
      'removalMode', false,
      'winner', null
    )
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 20,
    '{"type":"move","from":0,"to":23}'
  )$$,
  'a player with three pieces can fly'
);

update public.games
set revision = 30,
    game_state = jsonb_build_object(
      'board',
      '["P1",null,"P2","P1",null,"P2","P1",null,"P2","P1",null,null,null,null,"P2",null,null,null,null,null,null,null,null,null]'::jsonb,
      'currentPlayer', 'P1',
      'phase', 'movement',
      'piecesToPlace', '{"P1":0,"P2":0}'::jsonb,
      'piecesOnBoard', '{"P1":4,"P2":4}'::jsonb,
      'moveHistory',
      '{"P1":[{"from":0,"to":1},{"from":1,"to":0},{"from":0,"to":1},{"from":1,"to":0}],"P2":[]}'::jsonb,
      'removalMode', false,
      'winner', null
    )
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 30,
    '{"type":"move","from":0,"to":1}'
  )$$,
  'P0001',
  'The same piece cannot move back and forth more than twice',
  'the third back-and-forth cycle is rejected'
);

update public.games
set revision = 40,
    game_state = jsonb_build_object(
      'board',
      '["P2","P2","P2","P2",null,null,null,null,null,"P1","P1","P1",null,null,null,null,null,null,null,null,null,"P1",null,null]'::jsonb,
      'currentPlayer', 'P1',
      'phase', 'movement',
      'piecesToPlace', '{"P1":0,"P2":0}'::jsonb,
      'piecesOnBoard', '{"P1":4,"P2":4}'::jsonb,
      'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
      'removalMode', true,
      'winner', null
    )
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 40,
    '{"type":"remove","position":0}'
  )$$,
  'P0001',
  'A piece in a mill cannot be removed while another piece is available',
  'a protected mill piece cannot be removed'
);

update public.games
set revision = 50,
    game_state = jsonb_build_object(
      'board',
      '["P2","P2","P2",null,null,null,null,null,null,"P1","P1","P1",null,null,null,null,null,null,null,null,null,"P1",null,null]'::jsonb,
      'currentPlayer', 'P1',
      'phase', 'movement',
      'piecesToPlace', '{"P1":0,"P2":0}'::jsonb,
      'piecesOnBoard', '{"P1":4,"P2":3}'::jsonb,
      'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
      'removalMode', true,
      'winner', null
    )
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select lives_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 50,
    '{"type":"remove","position":0}'
  )$$,
  'a mill piece can be removed when all opponent pieces are in mills'
);
select is(
  (select game_state ->> 'winner' from public.games
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'P1',
  'dropping the opponent below three pieces records the winner'
);
select is(
  (select status from public.games
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'finished',
  'a winning action finishes the game'
);

update public.games
set revision = 60,
    status = 'active',
    game_state = jsonb_build_object(
      'board', to_jsonb(array_fill(null::text, array[24])),
      'currentPlayer', 'P1',
      'phase', 'placement',
      'piecesToPlace', '{"P1":9,"P2":9}'::jsonb,
      'piecesOnBoard', '{"P1":0,"P2":0}'::jsonb,
      'moveHistory', '{"P1":[],"P2":[]}'::jsonb,
      'removalMode', false,
      'winner', null
    )
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 60,
    '{"type":"place"}'
  )$$,
  'P0001',
  'Invalid board position',
  'a malformed action is rejected'
);
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 59,
    '{"type":"place","position":0}'
  )$$,
  'P0001',
  'Game state has changed; refresh and try again',
  'a stale revision is rejected'
);
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 60,
    '{"type":"replace_state","board":[]}'
  )$$,
  'P0001',
  'Unknown game action',
  'an unknown action cannot replace server state'
);

select set_config(
  'request.jwt.claim.sub',
  '33333333-3333-3333-3333-333333333333',
  true
);
set local role authenticated;
select is(
  (select count(*)::integer from public.games
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'RLS hides a game from a non-participant'
);
reset role;
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 60,
    '{"type":"place","position":0}'
  )$$,
  'P0001',
  'It is not your turn',
  'a non-participant cannot submit an action'
);

select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 60,
    '{"type":"place","position":"not-a-number"}'
  )$$,
  '22P02',
  'invalid input syntax for type integer: "not-a-number"',
  'a non-numeric position is rejected'
);
update public.games
set status = 'finished'
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 60,
    '{"type":"place","position":0}'
  )$$,
  'P0001',
  'Game is not active',
  'actions are rejected after the game is finished'
);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.submit_game_action(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 60,
    '{"type":"place","position":0}'
  )$$,
  'P0001',
  'Authentication required',
  'unauthenticated actions are rejected'
);

select * from finish();
rollback;
