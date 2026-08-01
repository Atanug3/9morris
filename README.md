# 9 Men's Morris

A browser-based implementation of 9 Men's Morris using HTML, CSS, and vanilla JavaScript. It supports playing against the computer or sharing the same device with another player.

## How to run

1. Clone or download the repository.
2. Open `index.html` in a modern web browser.

No build step or server is required.

## Gameplay

- Choose **One player vs Computer** or **Two players** from the game-mode selector.
- Use the **Sound** checkbox to turn move, mill, capture, and victory sounds on or off.
- In one-player mode, Player 1 plays against a computer opponent that forms mills, simulates Player 1's next legal moves to block mill threats, and chooses from valid moves.
- In two-player mode, both players share the same device.
- During the **placement phase**, players take turns placing their 9 pieces.
- Forming a **mill** allows the current player to remove one opponent piece.
- After placement, the game enters the **movement phase**, where pieces move to adjacent connected positions.
- When a player has only 3 pieces left, they may **fly** to any open position.
- A player may move the same piece back and forth for at most two consecutive cycles. The third cycle is blocked until a different move is made.
- A player wins when the opponent has fewer than 3 pieces or no legal moves.

## Notes

This is a lightweight starter implementation intended to be easy to review and extend.
