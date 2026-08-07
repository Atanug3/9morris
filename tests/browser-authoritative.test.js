const fs = require('fs');
const vm = require('vm');

const elements = new Map();
const rpcCalls = [];
const testUser = {
  id: 'user-1',
  email: 'one@example.test',
  user_metadata: { full_name: 'One' },
};

function element() {
  return {
    value: 'computer',
    checked: false,
    hidden: false,
    disabled: false,
    textContent: '',
    innerHTML: '',
    style: {},
    setAttribute() {},
    appendChild() {},
    addEventListener() {},
  };
}

const acceptedState = {
  board: Array(24).fill(null),
  currentPlayer: 'P2',
  phase: 'placement',
  piecesToPlace: { P1: 8, P2: 9 },
  piecesOnBoard: { P1: 1, P2: 0 },
  moveHistory: { P1: [], P2: [] },
  removalMode: false,
  winner: null,
};
acceptedState.board[0] = 'P1';

const client = {
  auth: {
    getSession: async () => ({ data: { session: { user: testUser } }, error: null }),
    onAuthStateChange() {},
    signInWithOAuth: async () => ({ error: null }),
    signOut: async () => ({ error: null }),
  },
  rpc(name, args) {
    rpcCalls.push({ name, args });
    return {
      single: async () => ({
        data: {
          id: 'game-1',
          room_code: 'ABC123',
          player1: 'user-1',
          player2: 'user-2',
          player1_name: 'One',
          player2_name: 'Two',
          status: 'active',
          revision: 1,
          game_state: acceptedState,
        },
        error: null,
      }),
    };
  },
  channel() {
    return {
      on() {
        return this;
      },
      subscribe() {
        return this;
      },
    };
  },
  removeChannel: async () => {},
  from() {
    return {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      single: async () => ({ data: null, error: null }),
      maybeSingle: async () => ({ data: null, error: null }),
    };
  },
};

const context = {
  console,
  Math,
  URL,
  URLSearchParams,
  testUser,
  rpcCalls,
  navigator: { clipboard: { writeText: async () => {} } },
  document: {
    getElementById(id) {
      if (!elements.has(id)) {
        elements.set(id, element());
      }
      return elements.get(id);
    },
    createElementNS() {
      return element();
    },
  },
  window: {
    SUPABASE_CONFIG: {
      url: 'https://test.supabase.co',
      anonKey: 'sb_publishable_test',
    },
    supabase: { createClient: () => client },
    location: {
      origin: 'https://example.test',
      pathname: '/',
      search: '',
      href: 'https://example.test/',
    },
    history: { replaceState() {} },
    setTimeout() {
      return 1;
    },
    clearTimeout() {},
    setInterval() {
      return 2;
    },
    clearInterval() {},
  },
};

vm.createContext(context);

const tests = `
(async () => {
  function assert(condition, message) {
    if (!condition) {
      throw new Error(message);
    }
  }

  await Promise.resolve();
  await Promise.resolve();

  resetBoardState();
  state.board[0] = 'P2';
  state.board[1] = 'P2';
  assert(chooseComputerPlacement() === 2, 'Computer mode regressed');

  resetBoardState();
  state.gameMode = 'online';
  currentUser = testUser;
  onlineGame = {
    id: 'game-1',
    room_code: 'ABC123',
    player1: 'user-1',
    player2: 'user-2',
    player1_name: 'One',
    player2_name: 'Two',
    status: 'active',
    revision: 0,
    player: 'P1',
    game_state: serializeGameState(),
  };

  const before = JSON.stringify(state.board);
  const pending = submitOnlineAction({ type: 'place', position: 0 });
  assert(
    JSON.stringify(state.board) === before,
    'Online action mutated the board before the server response',
  );

  await pending;

  assert(
    rpcCalls.length === 1 && rpcCalls[0].name === 'submit_game_action',
    'Online mode did not call the authoritative action RPC',
  );
  assert(
    !('p_game_state' in rpcCalls[0].args),
    'Online mode sent a client-generated replacement game state',
  );
  assert(
    state.board[0] === 'P1' && state.currentPlayer === 'P2',
    'The server-returned state was not applied',
  );

  rpcCalls.length = 0;
  onlineSavePending = false;
  state.board = Array(24).fill(null);
  state.board[0] = 'P1';
  state.board[3] = 'P1';
  state.board[6] = 'P1';
  state.currentPlayer = 'P1';
  state.phase = 'placement';
  state.piecesToPlace = { P1: 6, P2: 6 };
  state.piecesOnBoard = { P1: 3, P2: 3 };
  state.selected = null;
  onlineGame.revision = 5;
  onlineGame.game_state = serializeGameState();

  handleOnlinePositionClick(0);
  assert(state.selected === 0, 'A placed piece was not selectable after three placements');
  handleOnlinePositionClick(1);
  await Promise.resolve();
  await Promise.resolve();
  assert(
    rpcCalls.length === 1
      && rpcCalls[0].args.p_action.type === 'move'
      && rpcCalls[0].args.p_action.from === 0
      && rpcCalls[0].args.p_action.to === 1,
    'Mixed placement phase did not submit a movement action',
  );

  rpcCalls.length = 0;
  onlineSavePending = false;
  state.board = Array(24).fill(null);
  state.board[0] = 'P1';
  state.board[3] = 'P1';
  state.board[6] = 'P1';
  state.currentPlayer = 'P1';
  state.phase = 'placement';
  state.piecesToPlace = { P1: 6, P2: 6 };
  state.piecesOnBoard = { P1: 3, P2: 3 };
  state.selected = null;
  onlineGame.revision = 6;
  onlineGame.game_state = serializeGameState();

  handleOnlinePositionClick(2);
  await Promise.resolve();
  await Promise.resolve();
  assert(
    rpcCalls.length === 1
      && rpcCalls[0].args.p_action.type === 'place'
      && rpcCalls[0].args.p_action.position === 2,
    'Mixed placement phase did not preserve placement actions',
  );

  resetBoardState();
  state.phase = 'placement';
  state.currentPlayer = 'P1';
  state.piecesToPlace = { P1: 6, P2: 0 };
  state.piecesOnBoard = { P1: 3, P2: 2 };
  checkWinner();
  assert(state.winner === 'P1', 'Mixed-phase local win detection was skipped');

  console.log('Authoritative browser tests passed.');
})()
`;

const result = vm.runInContext(
  fs.readFileSync('script.js', 'utf8') + tests,
  context,
);

Promise.resolve(result).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
