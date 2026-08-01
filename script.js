const positions = {
  0: { x: 50, y: 50 },
  1: { x: 350, y: 50 },
  2: { x: 650, y: 50 },
  3: { x: 150, y: 150 },
  4: { x: 350, y: 150 },
  5: { x: 550, y: 150 },
  6: { x: 250, y: 250 },
  7: { x: 350, y: 250 },
  8: { x: 450, y: 250 },
  9: { x: 50, y: 350 },
  10: { x: 150, y: 350 },
  11: { x: 250, y: 350 },
  12: { x: 450, y: 350 },
  13: { x: 550, y: 350 },
  14: { x: 650, y: 350 },
  15: { x: 250, y: 450 },
  16: { x: 350, y: 450 },
  17: { x: 450, y: 450 },
  18: { x: 150, y: 550 },
  19: { x: 350, y: 550 },
  20: { x: 550, y: 550 },
  21: { x: 50, y: 650 },
  22: { x: 350, y: 650 },
  23: { x: 650, y: 650 },
};

const adjacency = {
  0: [1, 9],
  1: [0, 2, 4],
  2: [1, 14],
  3: [4, 10],
  4: [1, 3, 5, 7],
  5: [4, 13],
  6: [7, 11],
  7: [4, 6, 8],
  8: [7, 12],
  9: [0, 10, 21],
  10: [3, 9, 11, 18],
  11: [6, 10, 15],
  12: [8, 13, 17],
  13: [5, 12, 14, 20],
  14: [2, 13, 23],
  15: [11, 16],
  16: [15, 17, 19],
  17: [12, 16],
  18: [10, 19],
  19: [16, 18, 20, 22],
  20: [13, 19],
  21: [9, 22],
  22: [19, 21, 23],
  23: [14, 22],
};

const mills = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [15, 16, 17], [18, 19, 20], [21, 22, 23],
  [0, 9, 21], [3, 10, 18], [6, 11, 15],
  [1, 4, 7], [16, 19, 22],
  [8, 12, 17], [5, 13, 20], [2, 14, 23],
  [9, 10, 11], [12, 13, 14],
];

const boardLines = [
  [0, 1], [1, 2], [0, 9], [2, 14], [9, 21], [14, 23], [21, 22], [22, 23],
  [3, 4], [4, 5], [3, 10], [5, 13], [10, 18], [13, 20], [18, 19], [19, 20],
  [6, 7], [7, 8], [6, 11], [8, 12], [11, 15], [12, 17], [15, 16], [16, 17],
  [1, 4], [4, 7], [9, 10], [10, 11], [12, 13], [13, 14], [16, 19], [19, 22],
];

const state = {
  board: Array(24).fill(null),
  currentPlayer: 'P1',
  gameMode: 'computer',
  phase: 'placement',
  piecesToPlace: { P1: 9, P2: 9 },
  piecesOnBoard: { P1: 0, P2: 0 },
  moveHistory: { P1: [], P2: [] },
  selected: null,
  removalMode: false,
  winner: null,
};

const boardEl = document.getElementById('board');
const turnIndicator = document.getElementById('turn-indicator');
const phaseIndicator = document.getElementById('phase-indicator');
const statusMessage = document.getElementById('status-message');
const resetButton = document.getElementById('reset-button');
const gameModeSelect = document.getElementById('game-mode');
const soundEnabled = document.getElementById('sound-enabled');
let computerTimer = null;
let audioContext = null;

function playTone(frequency, duration, delay = 0, volume = 0.08) {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!soundEnabled.checked || !AudioContextClass) {
    return;
  }

  if (audioContext === null) {
    audioContext = new AudioContextClass();
  }

  if (audioContext.state === 'suspended') {
    audioContext.resume();
  }

  const startTime = audioContext.currentTime + delay;
  const oscillator = audioContext.createOscillator();
  const gain = audioContext.createGain();
  oscillator.type = 'sine';
  oscillator.frequency.setValueAtTime(frequency, startTime);
  gain.gain.setValueAtTime(volume, startTime);
  gain.gain.exponentialRampToValueAtTime(0.001, startTime + duration);
  oscillator.connect(gain);
  gain.connect(audioContext.destination);
  oscillator.start(startTime);
  oscillator.stop(startTime + duration);
}

function playSound(type) {
  const sounds = {
    move: [[330, 0.1, 0]],
    mill: [[440, 0.14, 0], [660, 0.18, 0.1]],
    capture: [[220, 0.2, 0]],
    win: [[523, 0.16, 0], [659, 0.16, 0.14], [784, 0.28, 0.28]],
  };

  sounds[type].forEach(([frequency, duration, delay]) => {
    playTone(frequency, duration, delay);
  });
}

function playerLabel(player) {
  if (player === 'P1') {
    return 'Player 1';
  }

  return state.gameMode === 'computer' ? 'Computer' : 'Player 2';
}

function otherPlayer(player) {
  return player === 'P1' ? 'P2' : 'P1';
}

function isComputerTurn() {
  return state.gameMode === 'computer' && state.currentPlayer === 'P2' && !state.winner;
}

function isMill(position, player, board = state.board) {
  return mills.some((mill) => mill.includes(position) && mill.every((p) => board[p] === player));
}

function allPiecesInMills(player, board = state.board) {
  const positionsForPlayer = board
    .map((value, index) => ({ value, index }))
    .filter((entry) => entry.value === player)
    .map((entry) => entry.index);

  return positionsForPlayer.every((position) => isMill(position, player, board));
}

function wouldExceedBackAndForthLimit(player, from, to) {
  const history = state.moveHistory[player];
  if (history.length < 4) {
    return false;
  }

  const [first, second, third, fourth] = history.slice(-4);
  return first.from === from
    && first.to === to
    && second.from === to
    && second.to === from
    && third.from === from
    && third.to === to
    && fourth.from === to
    && fourth.to === from;
}

function recordMove(player, from, to) {
  state.moveHistory[player].push({ from, to });
  state.moveHistory[player] = state.moveHistory[player].slice(-4);
}

function canMoveOnBoard(board, from, to, player) {
  if (board[from] !== player || board[to] !== null) {
    return false;
  }

  if (wouldExceedBackAndForthLimit(player, from, to)) {
    return false;
  }

  if (board.filter((value) => value === player).length === 3) {
    return true;
  }

  return adjacency[from].includes(to);
}

function canMove(from, to, player) {
  return canMoveOnBoard(state.board, from, to, player);
}

function hasLegalMove(player) {
  const occupied = state.board
    .map((value, index) => ({ value, index }))
    .filter((entry) => entry.value === player)
    .map((entry) => entry.index);

  return occupied.some((from) => state.board.some(
    (spot, to) => spot === null && canMove(from, to, player),
  ));
}

function updatePhase() {
  if (state.piecesToPlace.P1 === 0 && state.piecesToPlace.P2 === 0) {
    state.phase = 'movement';
  } else {
    state.phase = 'placement';
  }
}

function checkWinner() {
  if (state.phase === 'placement') {
    return;
  }

  const opponent = otherPlayer(state.currentPlayer);
  if (state.piecesOnBoard[opponent] < 3 || !hasLegalMove(opponent)) {
    state.winner = state.currentPlayer;
    playSound('win');
  }
}

function switchTurn() {
  updatePhase();
  checkWinner();

  if (!state.winner) {
    state.currentPlayer = otherPlayer(state.currentPlayer);
    state.selected = null;
  }

  render();
}

function removablePositions(player, board = state.board) {
  const opponent = otherPlayer(player);
  const opponentPositions = board
    .map((value, index) => value === opponent ? index : null)
    .filter((position) => position !== null);
  const positionsOutsideMills = opponentPositions.filter(
    (position) => !isMill(position, opponent, board),
  );

  return positionsOutsideMills.length > 0 ? positionsOutsideMills : opponentPositions;
}

function removeOpponentPiece(position) {
  const opponent = otherPlayer(state.currentPlayer);
  if (state.board[position] !== opponent) {
    statusMessage.textContent = 'You must remove an opponent piece.';
    return;
  }

  if (isMill(position, opponent) && !allPiecesInMills(opponent)) {
    statusMessage.textContent = 'You cannot remove a piece from a mill unless no other pieces are available.';
    return;
  }

  state.board[position] = null;
  state.piecesOnBoard[opponent] -= 1;
  state.removalMode = false;
  playSound('capture');
  statusMessage.textContent = `${playerLabel(opponent)} lost a piece.`;
  switchTurn();
}

function handlePlacement(position) {
  if (state.board[position] !== null) {
    statusMessage.textContent = 'That position is already occupied.';
    return;
  }

  state.board[position] = state.currentPlayer;
  state.piecesToPlace[state.currentPlayer] -= 1;
  state.piecesOnBoard[state.currentPlayer] += 1;
  playSound('move');

  if (isMill(position, state.currentPlayer)) {
    state.removalMode = true;
    playSound('mill');
    statusMessage.textContent = `${playerLabel(state.currentPlayer)} formed a mill. Remove one opponent piece.`;
    render();
    return;
  }

  switchTurn();
}

function handleMovement(position) {
  if (state.selected === null) {
    if (state.board[position] !== state.currentPlayer) {
      statusMessage.textContent = 'Select one of your own pieces to move.';
      return;
    }
    state.selected = position;
    statusMessage.textContent = `Selected position ${position + 1}. Choose a destination.`;
    render();
    return;
  }

  if (position === state.selected) {
    state.selected = null;
    statusMessage.textContent = 'Selection cleared.';
    render();
    return;
  }

  if (wouldExceedBackAndForthLimit(state.currentPlayer, state.selected, position)) {
    statusMessage.textContent = 'That piece cannot move back and forth more than twice. Choose another move.';
    return;
  }

  if (!canMove(state.selected, position, state.currentPlayer)) {
    statusMessage.textContent = 'Illegal move for the current phase.';
    return;
  }

  const movedFrom = state.selected;
  state.board[position] = state.currentPlayer;
  state.board[movedFrom] = null;
  const movedTo = position;
  state.selected = null;
  recordMove(state.currentPlayer, movedFrom, movedTo);
  playSound('move');

  if (isMill(movedTo, state.currentPlayer)) {
    state.removalMode = true;
    playSound('mill');
    statusMessage.textContent = `${playerLabel(state.currentPlayer)} formed a mill. Remove one opponent piece.`;
    render();
    return;
  }

  switchTurn();
}

function handlePositionClick(position) {
  if (state.winner || isComputerTurn()) {
    return;
  }

  if (state.removalMode) {
    removeOpponentPiece(position);
    return;
  }

  if (state.phase === 'placement') {
    handlePlacement(position);
  } else {
    handleMovement(position);
  }

  render();
}

function renderBoard() {
  boardEl.innerHTML = '';

  boardLines.forEach(([start, end]) => {
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    line.setAttribute('x1', positions[start].x);
    line.setAttribute('y1', positions[start].y);
    line.setAttribute('x2', positions[end].x);
    line.setAttribute('y2', positions[end].y);
    line.setAttribute('class', 'board-line');
    boardEl.appendChild(line);
  });

  Object.entries(positions).forEach(([key, pos]) => {
    const index = Number(key);
    const group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    group.style.cursor = 'pointer';
    group.addEventListener('click', () => handlePositionClick(index));

    const node = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    node.setAttribute('cx', pos.x);
    node.setAttribute('cy', pos.y);
    node.setAttribute('r', 22);
    node.setAttribute('class', `node${state.selected === index ? ' highlight' : ''}`);
    group.appendChild(node);

    if (state.board[index]) {
      const piece = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      piece.setAttribute('cx', pos.x);
      piece.setAttribute('cy', pos.y);
      piece.setAttribute('r', 16);
      piece.setAttribute('class', `piece ${state.board[index] === 'P1' ? 'player1' : 'player2'}`);
      group.appendChild(piece);
    }

    boardEl.appendChild(group);
  });
}

function renderStatus() {
  turnIndicator.textContent = playerLabel(state.currentPlayer);
  phaseIndicator.textContent = state.phase === 'placement'
    ? 'Placement'
    : state.piecesOnBoard[state.currentPlayer] === 3
      ? 'Flying'
      : 'Movement';

  if (state.winner) {
    statusMessage.textContent = `${playerLabel(state.winner)} wins!`;
  } else if (isComputerTurn()) {
    statusMessage.textContent = state.removalMode
      ? 'Computer formed a mill and is choosing a piece to remove.'
      : 'Computer is thinking...';
  } else if (!state.removalMode && state.phase === 'placement') {
    statusMessage.textContent = `${playerLabel(state.currentPlayer)}, place a piece.`;
  } else if (!state.removalMode && state.phase === 'movement') {
    const mode = state.piecesOnBoard[state.currentPlayer] === 3 ? 'fly' : 'move';
    statusMessage.textContent = `${playerLabel(state.currentPlayer)}, select a piece to ${mode}.`;
  }
}

function render() {
  renderBoard();
  renderStatus();
  scheduleComputerTurn();
}

function resetGame() {
  if (computerTimer !== null) {
    window.clearTimeout(computerTimer);
    computerTimer = null;
  }

  state.board = Array(24).fill(null);
  state.currentPlayer = 'P1';
  state.gameMode = gameModeSelect.value;
  state.phase = 'placement';
  state.piecesToPlace = { P1: 9, P2: 9 };
  state.piecesOnBoard = { P1: 0, P2: 0 };
  state.moveHistory = { P1: [], P2: [] };
  state.selected = null;
  state.removalMode = false;
  state.winner = null;
  render();
}

function chooseBest(options, scoreOption) {
  let bestScore = -Infinity;
  let bestOptions = [];

  options.forEach((option) => {
    const score = scoreOption(option);
    if (score > bestScore) {
      bestScore = score;
      bestOptions = [option];
    } else if (score === bestScore) {
      bestOptions.push(option);
    }
  });

  return bestOptions[Math.floor(Math.random() * bestOptions.length)];
}

function countOpenMillOpportunities(board, player) {
  return mills.filter((mill) => {
    const playerPieces = mill.filter((position) => board[position] === player).length;
    const openPositions = mill.filter((position) => board[position] === null).length;
    return playerPieces === 2 && openPositions === 1;
  }).length;
}

function millCompletingPlacements(board, player) {
  return board
    .map((value, position) => {
      if (value !== null) {
        return null;
      }

      const simulatedBoard = [...board];
      simulatedBoard[position] = player;
      return isMill(position, player, simulatedBoard) ? position : null;
    })
    .filter((position) => position !== null);
}

function legalMovesForBoard(board, player) {
  const moves = [];

  board.forEach((value, from) => {
    if (value !== player) {
      return;
    }

    board.forEach((destinationValue, to) => {
      if (destinationValue === null && canMoveOnBoard(board, from, to, player)) {
        moves.push({ from, to });
      }
    });
  });

  return moves;
}

function countMillFormingMoves(board, player) {
  return legalMovesForBoard(board, player).filter(({ from, to }) => {
    const simulatedBoard = [...board];
    simulatedBoard[from] = null;
    simulatedBoard[to] = player;
    return isMill(to, player, simulatedBoard);
  }).length;
}

function countImmediateMillThreats(board, player) {
  if (state.piecesToPlace[player] > 0) {
    return millCompletingPlacements(board, player).length;
  }

  return countMillFormingMoves(board, player);
}

function chooseComputerPlacement() {
  const openPositions = state.board
    .map((value, index) => value === null ? index : null)
    .filter((position) => position !== null);
  const opponentMillPositions = new Set(millCompletingPlacements(state.board, 'P1'));

  return chooseBest(openPositions, (position) => {
    const computerBoard = [...state.board];
    computerBoard[position] = 'P2';
    let score = adjacency[position].length;

    if (isMill(position, 'P2', computerBoard)) {
      score += 10000;
    }
    if (opponentMillPositions.has(position)) {
      score += 8000;
    }

    score += countOpenMillOpportunities(computerBoard, 'P2') * 30;
    score -= millCompletingPlacements(computerBoard, 'P1').length * 1200;
    return score;
  });
}

function computerMoves() {
  return legalMovesForBoard(state.board, 'P2');
}

function chooseComputerMove() {
  const opponentThreatsBefore = countMillFormingMoves(state.board, 'P1');

  return chooseBest(computerMoves(), ({ from, to }) => {
    const computerBoard = [...state.board];
    computerBoard[from] = null;
    computerBoard[to] = 'P2';
    const opponentThreatsAfter = countMillFormingMoves(computerBoard, 'P1');
    let score = adjacency[to].length;

    if (isMill(to, 'P2', computerBoard)) {
      score += 10000;
    }

    score += (opponentThreatsBefore - opponentThreatsAfter) * 3000;
    score -= opponentThreatsAfter * 1500;
    score += countOpenMillOpportunities(computerBoard, 'P2') * 30;
    return score;
  });
}

function chooseComputerRemoval() {
  const opponentThreatsBefore = countImmediateMillThreats(state.board, 'P1');

  return chooseBest(removablePositions('P2'), (position) => {
    const boardAfterRemoval = [...state.board];
    boardAfterRemoval[position] = null;
    const blockedThreats = opponentThreatsBefore
      - countImmediateMillThreats(boardAfterRemoval, 'P1');
    return blockedThreats * 3000 + adjacency[position].length;
  });
}

function performComputerTurn() {
  computerTimer = null;

  if (!isComputerTurn()) {
    return;
  }

  if (state.removalMode) {
    removeOpponentPiece(chooseComputerRemoval());
    return;
  }

  if (state.phase === 'placement') {
    handlePlacement(chooseComputerPlacement());
    return;
  }

  const move = chooseComputerMove();
  if (!move) {
    state.winner = 'P1';
    playSound('win');
    render();
    return;
  }

  state.board[move.from] = null;
  state.board[move.to] = 'P2';
  recordMove('P2', move.from, move.to);
  playSound('move');

  if (isMill(move.to, 'P2')) {
    state.removalMode = true;
    playSound('mill');
    render();
    return;
  }

  switchTurn();
}

function scheduleComputerTurn() {
  if (!isComputerTurn() || computerTimer !== null) {
    return;
  }

  computerTimer = window.setTimeout(performComputerTurn, 500);
}

resetButton.addEventListener('click', resetGame);
gameModeSelect.addEventListener('change', resetGame);
render();
