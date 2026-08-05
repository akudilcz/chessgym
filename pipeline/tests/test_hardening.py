"""
Regression tests for pipeline robustness fixes: malformed-row tolerance,
impossible-position rejection, famous-position survival, sigmoid clamping,
and a minimal end-to-end run of the streaming entry point.

Run with:

    .venv/bin/python -m pytest pipeline/tests/test_hardening.py
"""
from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from pipeline.run_stream import cheap_csv_predicate, stream
from pipeline.stages.filter_and_bucket import stratified_sample
from pipeline.stages.load import load_lichess_csv
from pipeline.stages.score import score_all
from pipeline.stages.themes import ThemeTaxonomy, apply_themes
from pipeline.stages.validate import validate
from pipeline.tests.test_pipeline import make_puzzle

PIPELINE = Path(__file__).resolve().parents[1]

CSV_HEADER = (
    "PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,"
    "Themes,GameUrl,OpeningTags\n"
)

#: Black to move (setup h7h6), then white mates with Ra8. Legal all the way.
GOOD_FEN = "6k1/5ppp/8/8/8/8/5PPP/R4K2 b - - 0 1"
GOOD_MOVES = "h7h6 a1a8"


def good_row(pid: str, themes: str = "mateIn1") -> str:
    return f"{pid},{GOOD_FEN},{GOOD_MOVES},1200,70,90,2000,{themes},,\n"


class LoadHardeningTests(unittest.TestCase):
    def test_malformed_rows_are_skipped_not_fatal(self):
        rows = [
            CSV_HEADER,
            good_row("ok1"),
            # Truncated row: DictReader yields None for missing columns.
            "trunc1\n",
            # Bad FEN.
            f"badfen,not a fen,{GOOD_MOVES},1200,70,90,2000,mateIn1,,\n",
            # Illegal setup move for the position.
            f"badsetup,{GOOD_FEN},e2e4 a1a8,1200,70,90,2000,mateIn1,,\n",
            # Non-numeric rating.
            f"badnum,{GOOD_FEN},{GOOD_MOVES},abc,70,90,2000,mateIn1,,\n",
            good_row("ok2"),
        ]
        with tempfile.TemporaryDirectory() as d:
            csv_path = Path(d) / "in.csv"
            csv_path.write_text("".join(rows))
            loaded = list(load_lichess_csv(csv_path))
        self.assertEqual(sorted(p.id for p in loaded), ["ok1", "ok2"])


class ValidatePositionTests(unittest.TestCase):
    def test_impossible_position_rejected(self):
        # Adjacent kings parse as FEN syntax but are not a legal position.
        p = make_puzzle(
            fen="k7/K7/8/8/8/8/8/R7 w - - 0 1",
            setup_move="",
            moves_uci=["a1a8"],
        )
        kept, rej = validate([p])
        self.assertEqual(kept, [])
        self.assertEqual(len(rej), 1)
        self.assertIn("illegal position", rej[0][1])


class ScoreClampTests(unittest.TestCase):
    def test_extreme_outlier_stays_finite_and_bounded(self):
        tax = ThemeTaxonomy(PIPELINE / "themes.yaml")
        puzzles = [make_puzzle(id=f"p{i}") for i in range(40)]
        # One grotesque outlier in every corpus-wide feature.
        puzzles.append(
            make_puzzle(id="outlier", popularity=100, nb_plays=10**9,
                        rating_dev=500))
        puzzles = apply_themes(puzzles, tax)
        scored = score_all(puzzles)  # must not raise OverflowError
        for p in scored:
            self.assertTrue(0.0 <= p.interest <= 1.0, p.id)


class FamousSurvivalTests(unittest.TestCase):
    def test_stratified_sample_never_drops_famous(self):
        # A famous position with rock-bottom interest among a full quota of
        # higher-interest lichess puzzles must still land.
        lichess = [make_puzzle(id=f"p{i}") for i in range(50)]
        for p in lichess:
            p.interest = 0.9
        famous = make_puzzle(
            id="reti", origin_kind="famous", popularity=0, nb_plays=0)
        famous.interest = 0.0
        out = stratified_sample(lichess + [famous], per_theme_target=5)
        self.assertIn("reti", [p.id for p in out])


class TaxonomyRobustnessTests(unittest.TestCase):
    def test_unknown_prereq_is_invalid_not_a_crash(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "themes.yaml"
            path.write_text(
                "themes:\n"
                "  - id: fork\n"
                "    display: Fork\n"
                "    description: d\n"
                "    importance: 1.0\n"
                "    prereqs: [doesNotExist]\n"
            )
            tax = ThemeTaxonomy(path)
            self.assertFalse(tax.prereqs_dag_valid())


class CheapPredicateTests(unittest.TestCase):
    def setUp(self):
        self.tax = ThemeTaxonomy(PIPELINE / "themes.yaml")

    def row(self, **kw):
        base = dict(Themes="mateIn1", RatingDeviation="70",
                    NbPlays="2000", Popularity="90")
        base.update(kw)
        return base

    def test_returns_canonical_for_passing_rows(self):
        got = cheap_csv_predicate(self.row(), set(), self.tax)
        self.assertEqual(got, ["mateIn1"])

    def test_rejects_unknown_theme_and_low_quality(self):
        self.assertIsNone(
            cheap_csv_predicate(self.row(Themes="unknown"), set(), self.tax))
        self.assertIsNone(
            cheap_csv_predicate(self.row(Popularity="10"), set(), self.tax))

    def test_rare_theme_relaxes_to_rd_only(self):
        row = self.row(Popularity="10", NbPlays="5", RatingDeviation="110")
        self.assertEqual(
            cheap_csv_predicate(row, {"mateIn1"}, self.tax), ["mateIn1"])


class StreamEndToEndTests(unittest.TestCase):
    def test_stream_builds_complete_corpus(self):
        rows = [CSV_HEADER]
        for i in range(12):
            rows.append(good_row(f"m{i}", themes="mateIn1"))
        for i in range(12):
            rows.append(good_row(f"f{i}", themes="fork"))
        # A duplicate id and a malformed row must not crash or double-count.
        rows.append(good_row("m0"))
        rows.append("garbage\n")

        with tempfile.TemporaryDirectory() as d:
            csv_path = Path(d) / "in.csv"
            csv_path.write_text("".join(rows))
            out = Path(d) / "out.sqlite"
            coverage = Path(d) / "coverage.json"
            tax = ThemeTaxonomy(PIPELINE / "themes.yaml")
            n = stream(
                csv_path,
                PIPELINE / "famous_positions.json",
                tax,
                out,
                per_theme=5,
                chunk_size=4,
                coverage_path=coverage,
                version="test",
                themes_path=PIPELINE / "themes.yaml",
            )

            conn = sqlite3.connect(str(out))
            (db_n,) = conn.execute("SELECT COUNT(*) FROM puzzles").fetchone()
            self.assertEqual(n, db_n, "return value must match the DB")
            # No duplicate ids survived.
            (dupes,) = conn.execute(
                "SELECT COUNT(*) - COUNT(DISTINCT id) FROM puzzles"
            ).fetchone()
            self.assertEqual(dupes, 0)
            # The corpus is finalized: meta present, daily index populated,
            # interest normalized into [0, 1].
            meta = conn.execute("SELECT * FROM corpus_meta").fetchall()
            self.assertEqual(len(meta), 1)
            (daily_n,) = conn.execute(
                "SELECT COUNT(*) FROM daily_index").fetchone()
            self.assertGreater(daily_n, 0)
            self.assertLessEqual(daily_n, max(30, db_n))
            for (interest,) in conn.execute("SELECT interest FROM puzzles"):
                self.assertTrue(0.0 <= interest <= 1.0)
            # Famous positions always land.
            famous_ids = [
                r[0] for r in conn.execute(
                    "SELECT id FROM puzzles WHERE origin_kind = 'famous'")
            ]
            self.assertTrue(famous_ids)
            conn.close()

            report = json.loads(coverage.read_text())
            self.assertEqual(report["n_puzzles"], db_n)


if __name__ == "__main__":
    unittest.main()
