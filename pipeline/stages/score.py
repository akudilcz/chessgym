"""
Stage 4: compute interestingness features and score for each puzzle.

See design/scoring.md for the exact formula. This module is pure:
deterministic given the same input puzzles, no I/O.
"""
from __future__ import annotations

import math
from statistics import median

import chess

from .load import Puzzle


PIECE_VALUES = {
    chess.PAWN: 1,
    chess.KNIGHT: 3,
    chess.BISHOP: 3,
    chess.ROOK: 5,
    chess.QUEEN: 9,
    chess.KING: 0,
}


def _material(board: chess.Board, color: bool) -> int:
    total = 0
    for pt, val in PIECE_VALUES.items():
        total += len(board.pieces(pt, color)) * val
    return total


def _board_after_setup(p: Puzzle) -> chess.Board:
    b = chess.Board(p.fen)
    if p.setup_move:
        b.push_uci(p.setup_move)
    return b


def compute_features(p: Puzzle, theme_frequency: dict[str, float]) -> dict:
    board = _board_after_setup(p)
    # First solver move.
    first_uci = p.moves_uci[0] if p.moves_uci else ""
    first_move = chess.Move.from_uci(first_uci) if first_uci else None

    # quiet_key: not check, not capture, not promotion.
    quiet_key = 0
    if first_move is not None:
        gives_check = board.gives_check(first_move)
        is_capture = board.is_capture(first_move)
        is_promo = first_move.promotion is not None
        if not gives_check and not is_capture and not is_promo:
            quiet_key = 1

    # sacrifice: material drop on any solver move in first 4 ply.
    solver_color = board.turn
    material_before = _material(board, solver_color)
    max_drop = 0
    sim = board.copy()
    for i, uci in enumerate(p.moves_uci[:4]):
        mv = chess.Move.from_uci(uci)
        if mv not in sim.legal_moves:
            break
        sim.push(mv)
        if i % 2 == 1:
            # After opponent move — measure our material vs start.
            now = _material(sim, solver_color)
            drop = material_before - now
            if drop > max_drop:
                max_drop = drop
    sacrifice = min(max(max_drop, 0), 3)

    # counter_intuitive (cheap proxy, no engine):
    # 0 if first move is the most valuable capture available OR any check.
    # 1 otherwise.
    counter_intuitive = 1
    if first_move is not None:
        legal = list(board.legal_moves)
        mvc_value = 0
        mvc_move = None
        for m in legal:
            if board.is_capture(m):
                cap_sq = m.to_square
                cap_piece = board.piece_at(cap_sq)
                if cap_piece is None and board.is_en_passant(m):
                    val = 1
                else:
                    val = PIECE_VALUES.get(cap_piece.piece_type, 0) if cap_piece else 0
                if val > mvc_value:
                    mvc_value = val
                    mvc_move = m
        if mvc_move is not None and first_move == mvc_move:
            counter_intuitive = 0
        elif board.gives_check(first_move):
            # A checking first move is the obvious try, so it is not
            # counter-intuitive. Note there is no need to also scan for
            # "does any check exist": if first_move gives check then one
            # trivially does, and the scan is the most expensive thing in
            # this function.
            counter_intuitive = 0

    # economy: pieces on board / 32.
    pieces_on_board = sum(len(board.pieces(pt, c))
                          for pt in PIECE_VALUES for c in (True, False))
    economy = pieces_on_board / 32.0

    # theme_rarity: from precomputed frequency map.
    primary = p.themes[0] if p.themes else ""
    freq = max(theme_frequency.get(primary, 1e-6), 1e-6)
    theme_rarity = 1.0 / freq

    # mate_bonus: last solver move ends in mate.
    mate_bonus = 0
    sim = board.copy()
    try:
        for uci in p.moves_uci:
            mv = chess.Move.from_uci(uci)
            if mv not in sim.legal_moves:
                sim = None
                break
            sim.push(mv)
        if sim is not None and sim.is_checkmate():
            mate_bonus = 1
    except ValueError:
        pass

    # underpromotion_bonus.
    underpromo_bonus = 0
    for uci in p.moves_uci:
        try:
            mv = chess.Move.from_uci(uci)
        except ValueError:
            continue
        if mv.promotion is not None and mv.promotion != chess.QUEEN:
            underpromo_bonus = 1
            break

    return {
        "popularity": p.popularity,
        "log_plays": math.log1p(p.nb_plays),
        "rating_dev": p.rating_dev,
        "quiet_key": quiet_key,
        "sacrifice": sacrifice,
        "counter_intuitive": counter_intuitive,
        "economy": economy,
        "theme_rarity": theme_rarity,
        "mate_bonus": mate_bonus,
        "underpromo_bonus": underpromo_bonus,
    }


def _zscore(values: list[float]) -> tuple[float, float]:
    if not values:
        return 0.0, 1.0
    mean = sum(values) / len(values)
    var = sum((v - mean) ** 2 for v in values) / max(len(values) - 1, 1)
    std = math.sqrt(var) or 1.0
    return mean, std


def _mad(values: list[float]) -> tuple[float, float]:
    if not values:
        return 0.0, 1.0
    med = median(values)
    mad = median([abs(v - med) for v in values]) or 1.0
    return med, mad


WEIGHTS = {
    "popularity": 1.0,
    "log_plays": 0.5,
    "rating_dev": -0.3,
    "quiet_key": 0.8,
    "sacrifice": 1.2,
    "counter_intuitive": 1.5,
    "economy": -0.4,
    "theme_rarity": 0.6,
    "mate_bonus": 0.5,
    "underpromo_bonus": 1.0,
}


def score_all(puzzles: list[Puzzle]) -> list[Puzzle]:
    # Theme frequency on the full set.
    theme_counts: dict[str, int] = {}
    for p in puzzles:
        if p.themes:
            theme_counts[p.themes[0]] = theme_counts.get(p.themes[0], 0) + 1
    total = sum(theme_counts.values()) or 1
    theme_frequency = {k: v / total for k, v in theme_counts.items()}

    for p in puzzles:
        p.features = compute_features(p, theme_frequency)

    # Z-normalize the z-scored features.
    pop_vals = [p.features["popularity"] for p in puzzles]
    plays_vals = [p.features["log_plays"] for p in puzzles]
    rd_vals = [p.features["rating_dev"] for p in puzzles]
    rarity_vals = [p.features["theme_rarity"] for p in puzzles]

    pop_m, pop_s = _zscore(pop_vals)
    plays_m, plays_s = _zscore(plays_vals)
    rd_m, rd_s = _zscore(rd_vals)
    rar_m, rar_s = _zscore(rarity_vals)

    raw_scores: list[float] = []
    for p in puzzles:
        f = p.features
        raw = (
            WEIGHTS["popularity"] * (f["popularity"] - pop_m) / pop_s
            + WEIGHTS["log_plays"] * (f["log_plays"] - plays_m) / plays_s
            + WEIGHTS["rating_dev"] * (f["rating_dev"] - rd_m) / rd_s
            + WEIGHTS["quiet_key"] * f["quiet_key"]
            + WEIGHTS["sacrifice"] * f["sacrifice"]
            + WEIGHTS["counter_intuitive"] * f["counter_intuitive"]
            + WEIGHTS["economy"] * f["economy"]
            + WEIGHTS["theme_rarity"] * (f["theme_rarity"] - rar_m) / rar_s
            + WEIGHTS["mate_bonus"] * f["mate_bonus"]
            + WEIGHTS["underpromo_bonus"] * f["underpromo_bonus"]
        )
        p.features["raw"] = raw
        raw_scores.append(raw)

    med, mad = _mad(raw_scores)
    for p in puzzles:
        z = (p.features["raw"] - med) / (1.4826 * mad)  # 1.4826 for normal consistency
        # Clamp the exponent: at corpus scale (or when MAD degenerates to
        # its 1.0 fallback) a single extreme outlier is enough to overflow
        # math.exp. Mirrors normalize_interest in run_stream.py.
        z = max(-60.0, min(60.0, z))
        p.interest = 1.0 / (1.0 + math.exp(-z))

    return puzzles
