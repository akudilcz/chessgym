"""
Smoke + unit tests for the curation pipeline. Run with:

    .venv/bin/python -m unittest -v pipeline.tests.test_pipeline
"""
from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from pipeline.stages.load import Puzzle, load_famous_json
from pipeline.stages.themes import ThemeTaxonomy, apply_themes
from pipeline.stages.score import score_all, compute_features
from pipeline.stages.filter_and_bucket import quality_filter, stratified_sample, rating_bucket
from pipeline.stages.emit import emit, source_hash_of
from pipeline.stages.validate import validate


PIPELINE = Path(__file__).resolve().parents[1]


def make_puzzle(**kw) -> Puzzle:
    defaults = dict(
        id="t1", fen="r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        setup_move="e1g1", side_to_move="b",
        moves_uci=["e8g8", "a1a8", "g8h8"],
        themes=["mateIn1"], lichess_themes=["mateIn1"],
        rating=1200, rating_dev=70, popularity=90, nb_plays=2000,
        origin_kind="lichess", origin_label=None, explanation=None,
    )
    defaults.update(kw)
    return Puzzle(**defaults)


class TaxonomyTests(unittest.TestCase):
    def setUp(self):
        self.tax = ThemeTaxonomy(PIPELINE / "themes.yaml")

    def test_dag_acyclic(self):
        self.assertTrue(self.tax.prereqs_dag_valid())

    def test_canonical_mapping(self):
        self.assertEqual(self.tax.canonical(["mateIn1"]), ["mateIn1"])
        self.assertEqual(self.tax.canonical(["underPromotion"]), ["underpromotion"])
        self.assertEqual(self.tax.canonical(["unknown"]), [])

    def test_all_prereqs_exist(self):
        for t in self.tax.themes:
            for pr in t.get("prereqs", []):
                self.assertIn(pr, self.tax.by_id, f"bad prereq {pr} on {t['id']}")


class ScoreTests(unittest.TestCase):
    def test_score_in_unit_interval(self):
        tax = ThemeTaxonomy(PIPELINE / "themes.yaml")
        puzzles = [make_puzzle(id=f"p{i}", rating=1000 + i * 50) for i in range(20)]
        puzzles = apply_themes(puzzles, tax)
        scored = score_all(puzzles)
        for p in scored:
            self.assertGreaterEqual(p.interest, 0.0)
            self.assertLessEqual(p.interest, 1.0)

    def test_features_flags(self):
        # Mate-delivering capture: quiet_key=0, counter_intuitive=0.
        p = make_puzzle(
            fen="7k/5ppp/8/8/8/8/5PPP/R3K2R w KQ - 0 1",
            setup_move="e1g1", moves_uci=["h7h6", "a1a8"],  # rook to 8th rank capture? not here
        )
        feats = compute_features(p, {"mateIn1": 1.0})
        self.assertIn("quiet_key", feats)
        self.assertIn("counter_intuitive", feats)


class FilterBucketTests(unittest.TestCase):
    def test_quality_drops_lowpop(self):
        # per_theme_target=0 makes every theme "common" in the filter, so
        # the strict popularity/plays/RD thresholds apply. A single low-pop
        # lichess puzzle under that regime is dropped.
        p = make_puzzle(popularity=10)
        self.assertEqual(quality_filter([p], per_theme_target=0), [])

    def test_quality_keeps_famous(self):
        p = make_puzzle(origin_kind="famous", popularity=0, nb_plays=0, rating_dev=300)
        self.assertEqual(len(quality_filter([p], per_theme_target=200)), 1)

    def test_rating_bucket(self):
        self.assertEqual(rating_bucket(1234), 1200)
        self.assertEqual(rating_bucket(100), 600)
        self.assertEqual(rating_bucket(3000), 2300)

    def test_stratified_respects_target(self):
        puzzles = [
            make_puzzle(id=f"p{i}", rating=1000 + (i % 5) * 100)
            for i in range(100)
        ]
        for p in puzzles:
            p.interest = 0.5
        out = stratified_sample(puzzles, per_theme_target=10)
        self.assertLessEqual(len(out), 10)


class EmitSmokeTest(unittest.TestCase):
    def test_end_to_end_emit(self):
        tax = ThemeTaxonomy(PIPELINE / "themes.yaml")
        puzzles = [make_puzzle(id=f"p{i}") for i in range(30)]
        puzzles = apply_themes(puzzles, tax)
        puzzles = score_all(puzzles)
        puzzles = quality_filter(puzzles, per_theme_target=200)
        self.assertTrue(puzzles, "quality filter should not empty the list")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "puzzles.sqlite"
            emit(puzzles, tax, out, version="test", source_hash="abc")
            conn = sqlite3.connect(str(out))
            (n,) = conn.execute("SELECT count(*) FROM puzzles").fetchone()
            self.assertEqual(n, len(puzzles))
            (nt,) = conn.execute("SELECT count(*) FROM themes").fetchone()
            self.assertEqual(nt, len(tax.themes))
            # FK integrity: every puzzle_theme points to an existing theme.
            for (tid,) in conn.execute("SELECT theme_id FROM puzzle_themes"):
                self.assertIn(tid, tax.by_id)
            conn.close()


class ValidateTests(unittest.TestCase):
    def test_valid_puzzle_kept(self):
        # Mate-in-1: white plays Qh7#. FEN pre-setup; setup is black move.
        # Simpler: no setup, direct solver move.
        p = make_puzzle(
            fen="6k1/5ppp/8/8/8/8/5PPP/R4K2 w - - 0 1",
            setup_move="",
            side_to_move="w",
            moves_uci=["a1a8"],
        )
        kept, rej = validate([p])
        self.assertEqual(len(kept), 1)
        self.assertEqual(rej, [])

    def test_illegal_move_rejected(self):
        p = make_puzzle(
            fen="6k1/5ppp/8/8/8/8/5PPP/R4K2 w - - 0 1",
            setup_move="",
            moves_uci=["a1a9"],  # invalid square
        )
        kept, rej = validate([p])
        self.assertEqual(kept, [])
        self.assertEqual(len(rej), 1)

    def test_non_legal_move_rejected(self):
        p = make_puzzle(
            fen="6k1/5ppp/8/8/8/8/5PPP/R4K2 w - - 0 1",
            setup_move="",
            moves_uci=["h1h8"],  # no rook on h1
        )
        kept, rej = validate([p])
        self.assertEqual(kept, [])

    def test_famous_positions_all_legal(self):
        # Verifies hand-curated famous_positions.json has legal solutions —
        # a regression guard for corpus maintenance.
        from pipeline.stages.load import load_famous_json
        puzzles = list(load_famous_json(PIPELINE / "famous_positions.json"))
        kept, rej = validate(puzzles)
        self.assertEqual(rej, [], f"famous positions have errors: {rej}")
        self.assertEqual(len(kept), len(puzzles))


class FamousJSONTests(unittest.TestCase):
    def test_key_move_belongs_to_the_solver(self):
        """The first move of a study is the puzzle, not the scene-setting.

        A Lichess row opens with the opponent's blunder, replayed before the
        player sees the board. A famous study has no such move. Consuming its
        first move as a setup move plays Reti's Kg7 / Lasker's queen sacrifice
        / Saavedra's c8=R *for* the player and flips the sides, so the player
        defends while the app performs the brilliancy.
        """
        famous = list(load_famous_json(PIPELINE / "famous_positions.json"))
        self.assertTrue(famous)
        for p in famous:
            raw = None
            for it in json.loads(
                    (PIPELINE / "famous_positions.json").read_text()):
                if it["id"] == p.id:
                    raw = it
                    break
            self.assertIsNotNone(raw, f"{p.id} missing from source json")
            declared_setup = raw.get("setup_move") or ""
            self.assertEqual(
                p.setup_move, declared_setup,
                f"{p.id}: setup_move was invented from the solution line",
            )
            first_solution_move = raw["solution_uci"].split()[0]
            if not declared_setup:
                self.assertEqual(
                    p.moves_uci[0], first_solution_move,
                    f"{p.id}: the study's key move {first_solution_move} was "
                    f"taken away from the solver",
                )

    def test_famous_solver_plays_the_side_to_move_in_the_fen(self):
        import chess
        famous = list(load_famous_json(PIPELINE / "famous_positions.json"))
        for p in famous:
            if p.setup_move:
                continue
            board = chess.Board(p.fen)
            expected = "w" if board.turn == chess.WHITE else "b"
            self.assertEqual(
                p.side_to_move, expected,
                f"{p.id}: solver is playing the wrong colour",
            )

    def test_load(self):
        famous = list(load_famous_json(PIPELINE / "famous_positions.json"))
        self.assertGreater(len(famous), 0)
        for p in famous:
            self.assertEqual(p.origin_kind, "famous")
            self.assertTrue(p.moves_uci)
            self.assertTrue(p.themes)


class DeterminismTests(unittest.TestCase):
    """The corpus is documented as reproducible; prove it byte-for-byte.

    `corpus_meta.built_at` is the one field that varies between runs, so the
    build honours SOURCE_DATE_EPOCH. With it pinned, two emits over identical
    inputs must produce identical files — otherwise a release cannot be
    verified and a rebuild silently churns a 58 MB asset.
    """

    def _corpus(self, out: Path, seed: int = 0) -> bytes:
        puzzles = [
            make_puzzle(
                id=f"d{i}",
                fen="6k1/5ppp/8/8/8/8/5PPP/R4K2 w - - 0 1",
                setup_move="",
                moves_uci=["a1a8"],
                themes=["fork"],
                rating=1000 + i,
                # Identical interest across rows: any daily_index ordering
                # that falls back to physical row order shows up here.
                popularity=90,
            )
            for i in range(12)
        ]
        tax = ThemeTaxonomy(PIPELINE / "themes.yaml")
        emit(puzzles, tax, out, version="test", source_hash="deadbeef")
        return out.read_bytes()

    def test_two_emits_are_byte_identical(self):
        import os
        os.environ["SOURCE_DATE_EPOCH"] = "1700000000"
        try:
            with tempfile.TemporaryDirectory() as d:
                pa, pb = Path(d) / "a.sqlite", Path(d) / "b.sqlite"
                a = self._corpus(pa)
                b = self._corpus(pb)
                # Byte-identity alone is a weak guard: two emits inside the
                # same wall-clock second agree even when built_at is NOT
                # pinned. Assert the stamp actually came from the epoch.
                conn = sqlite3.connect(str(pa))
                built_at = conn.execute(
                    "SELECT built_at FROM corpus_meta").fetchone()[0]
                conn.close()
            self.assertEqual(
                built_at, "2023-11-14T22:13:20+00:00",
                "corpus_meta.built_at ignored SOURCE_DATE_EPOCH — the "
                "artifact is not reproducible",
            )
            self.assertEqual(
                a, b,
                "two emits over identical inputs differ — the corpus is not "
                "reproducible",
            )
        finally:
            os.environ.pop("SOURCE_DATE_EPOCH", None)

    def test_source_date_epoch_pins_built_at(self):
        import os
        from pipeline.stages.emit import built_at_iso
        os.environ["SOURCE_DATE_EPOCH"] = "1700000000"
        try:
            self.assertEqual(built_at_iso(), "2023-11-14T22:13:20+00:00")
        finally:
            os.environ.pop("SOURCE_DATE_EPOCH", None)

    def test_daily_index_breaks_interest_ties_by_id(self):
        # Equal-interest puzzles must order by id, not by insertion order.
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "c.sqlite"
            self._corpus(out)
            conn = sqlite3.connect(str(out))
            ids = [r[0] for r in conn.execute(
                "SELECT puzzle_id FROM daily_index ORDER BY slot")]
            conn.close()
        tied = [i for i in ids if i.startswith("d")]
        self.assertEqual(tied, sorted(tied),
                         "daily_index ties are not resolved by id")


if __name__ == "__main__":
    unittest.main()
