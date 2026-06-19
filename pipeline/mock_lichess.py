"""
Generate a small synthetic Lichess-format puzzle CSV for pipeline development.

Produces four classes of puzzles from random-game positions:
  1. Mate-in-1  (Moves = setup + mate; theme = mateIn1)
  2. Mate-in-2  (Moves = setup + M1 + reply + M2; theme = mateIn2)
  3. Hanging-piece captures (take a free piece; theme = hangingPiece)
  4. Forks (move that attacks >= 2 pieces; theme = fork)

Intended for development only. The real input is the full Lichess puzzle
database under `input/lichess_db_puzzle.csv.zst`.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import random
import sys
from pathlib import Path

import chess


LICHESS_HEADER = [
    "PuzzleId", "FEN", "Moves", "Rating", "RatingDeviation",
    "Popularity", "NbPlays", "Themes", "GameUrl", "OpeningTags",
]

PIECE_VAL = {
    chess.PAWN: 1, chess.KNIGHT: 3, chess.BISHOP: 3,
    chess.ROOK: 5, chess.QUEEN: 9, chess.KING: 0,
}


def _find_mate_in_1(board: chess.Board) -> chess.Move | None:
    for move in board.legal_moves:
        board.push(move)
        is_mate = board.is_checkmate()
        board.pop()
        if is_mate:
            return move
    return None


def _find_mate_in_2(board: chess.Board) -> tuple[chess.Move, chess.Move, chess.Move] | None:
    """
    Find (our_first, opp_reply, our_mate) such that our_first forces mate in 2.
    For every opponent reply, we must have at least one mate-in-1.
    Return one concrete continuation tuple if solvable.
    """
    for m1 in board.legal_moves:
        board.push(m1)
        if board.is_checkmate():
            board.pop()
            continue
        opp_moves = list(board.legal_moves)
        if not opp_moves:
            board.pop()
            continue  # stalemate-like; skip
        all_forced = True
        sample_reply: chess.Move | None = None
        sample_mate: chess.Move | None = None
        for reply in opp_moves:
            board.push(reply)
            m2 = _find_mate_in_1(board)
            board.pop()
            if m2 is None:
                all_forced = False
                break
            if sample_reply is None:
                sample_reply = reply
                sample_mate = m2
        board.pop()
        if all_forced and sample_reply is not None and sample_mate is not None:
            return (m1, sample_reply, sample_mate)
    return None


def _is_fork(board: chess.Board, move: chess.Move) -> bool:
    """Move attacks at least two opposing pieces of value >= knight."""
    board.push(move)
    try:
        piece = board.piece_at(move.to_square)
        if piece is None:
            return False
        them = not piece.color
        targets = 0
        for sq in board.attacks(move.to_square):
            p = board.piece_at(sq)
            if p is not None and p.color == them and PIECE_VAL[p.piece_type] >= 3:
                targets += 1
        return targets >= 2
    finally:
        board.pop()


def _find_hanging_capture(board: chess.Board) -> chess.Move | None:
    """A capture where the destination square is undefended."""
    for move in board.legal_moves:
        if not board.is_capture(move):
            continue
        cap_sq = move.to_square
        # SEE lite: is the capturing piece attacked by any enemy pawn?
        attackers = board.attackers(not board.turn, cap_sq)
        if not attackers:
            # Destination is undefended after move — free capture.
            return move
    return None


def _synth_row(
    seed: int,
    fen_before_setup: str,
    setup: chess.Move,
    rest_uci: list[str],
    themes: list[str],
    rng: random.Random,
) -> dict:
    puzzle_id = hashlib.sha1(
        f"{seed}:{fen_before_setup}:{setup.uci()}".encode()
    ).hexdigest()[:6]
    moves = setup.uci() + " " + " ".join(rest_uci)
    # Difficulty scales with theme complexity.
    theme_bias = {
        "mateIn1": 0, "mateIn2": 400, "fork": 200, "hangingPiece": -200,
    }
    bias = max((theme_bias.get(t, 0) for t in themes), default=0)
    rating = int(rng.gauss(1300 + bias, 300))
    rating = max(500, min(2400, rating))
    rd = max(30, min(150, int(rng.gauss(70, 20))))
    pop = max(-100, min(100, int(rng.gauss(88, 8))))
    plays = int(abs(rng.gauss(5000, 3000))) + 500
    return {
        "PuzzleId": puzzle_id,
        "FEN": fen_before_setup,
        "Moves": moves.strip(),
        "Rating": rating,
        "RatingDeviation": rd,
        "Popularity": pop,
        "NbPlays": plays,
        "Themes": " ".join(themes),
        "GameUrl": f"https://lichess.org/synthetic/{puzzle_id}",
        "OpeningTags": "",
    }


def _position_themes(board: chess.Board, base: list[str]) -> list[str]:
    """Augment base themes with position-derived tags."""
    out = list(base)
    n_pieces = chess.popcount(board.occupied)
    if n_pieces <= 10 and "endgame" not in out:
        out.append("endgame")
    return out


def generate(n: int, out_path: Path, seed: int = 42) -> int:
    rng = random.Random(seed)
    rows: list[dict] = []
    tries = 0
    quotas = {
        "mateIn1": int(n * 0.35),
        "mateIn2": int(n * 0.20),
        "fork": int(n * 0.25),
        "hangingPiece": int(n * 0.20),
    }
    counts = {k: 0 for k in quotas}

    def need(theme: str) -> bool:
        return counts[theme] < quotas[theme]

    while sum(counts.values()) < sum(quotas.values()) and tries < n * 1000:
        tries += 1
        board = chess.Board()
        max_plies = rng.randint(8, 60)
        for _ in range(max_plies):
            if board.is_game_over():
                break
            moves = list(board.legal_moves)
            if not moves:
                break
            board.push(rng.choice(moves))

            # Try setup moves and see what puzzle kind the resulting position supports.
            setups = list(board.legal_moves)
            rng.shuffle(setups)
            for setup in setups[:6]:
                board.push(setup)
                pre_fen = None
                chosen_theme = None
                rest: list[str] = []
                # mate-in-1?
                if need("mateIn1"):
                    m1 = _find_mate_in_1(board)
                    if m1 is not None:
                        chosen_theme = "mateIn1"
                        rest = [m1.uci()]
                # mate-in-2 (more expensive).
                if chosen_theme is None and need("mateIn2") and rng.random() < 0.3:
                    m2 = _find_mate_in_2(board)
                    if m2 is not None:
                        chosen_theme = "mateIn2"
                        rest = [m2[0].uci(), m2[1].uci(), m2[2].uci()]
                # fork?
                if chosen_theme is None and need("fork"):
                    for cand in list(board.legal_moves)[:30]:
                        if _is_fork(board, cand):
                            chosen_theme = "fork"
                            rest = [cand.uci()]
                            break
                # hanging piece?
                if chosen_theme is None and need("hangingPiece"):
                    hc = _find_hanging_capture(board)
                    if hc is not None:
                        chosen_theme = "hangingPiece"
                        rest = [hc.uci()]

                board.pop()
                if chosen_theme is None:
                    continue
                themes = _position_themes(board, [chosen_theme])
                pre_fen = board.fen()
                rows.append(_synth_row(
                    len(rows), pre_fen, setup, rest, themes, rng))
                counts[chosen_theme] += 1
                break
            if sum(counts.values()) >= sum(quotas.values()):
                break
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=LICHESS_HEADER)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    return len(rows)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("-n", "--count", type=int, default=200)
    p.add_argument("-o", "--out", type=Path,
                   default=Path("pipeline/input/mock_lichess.csv"))
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    n_written = generate(args.count, args.out, args.seed)
    print(f"wrote {n_written} rows to {args.out}", file=sys.stderr)
    return 0 if n_written > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
