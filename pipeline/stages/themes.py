"""
Stage 3: remap raw Lichess theme tags to our canonical theme ids, and
derive a primary theme for each puzzle.
"""
from __future__ import annotations

from pathlib import Path

import yaml

from .load import Puzzle


class ThemeTaxonomy:
    def __init__(self, path: Path):
        with path.open() as fh:
            doc = yaml.safe_load(fh)
        self.themes = doc["themes"]
        self.by_id = {t["id"]: t for t in self.themes}
        # Build alias → canonical id map.
        self.alias_to_id: dict[str, str] = {}
        for t in self.themes:
            for alias in t.get("lichess_aliases", []):
                self.alias_to_id[alias] = t["id"]

    def canonical(self, lichess_tags: list[str]) -> list[str]:
        """Return canonical theme ids for a list of raw Lichess tags, preserving input order."""
        seen: set[str] = set()
        out: list[str] = []
        for tag in lichess_tags:
            cid = self.alias_to_id.get(tag)
            if cid and cid not in seen:
                seen.add(cid)
                out.append(cid)
        return out

    def prereqs_dag_valid(self) -> bool:
        """Verify the prereq graph is a DAG (no cycles)."""
        white, grey, black = 0, 1, 2
        color = {t["id"]: white for t in self.themes}

        def dfs(u: str) -> bool:
            color[u] = grey
            for v in self.by_id[u].get("prereqs", []):
                if v not in self.by_id:
                    # A prereq pointing at a nonexistent theme is a broken
                    # graph, not a KeyError for the caller to decipher.
                    return False
                if color.get(v, white) == grey:
                    return False
                if color.get(v, white) == white and not dfs(v):
                    return False
            color[u] = black
            return True

        return all(color[t["id"]] == black or dfs(t["id"]) for t in self.themes)

    def importance(self, theme_id: str) -> float:
        return self.by_id[theme_id]["importance"]


def apply_themes(puzzles: list[Puzzle], tax: ThemeTaxonomy) -> list[Puzzle]:
    """
    Fill `puzzle.themes` for Lichess-origin puzzles using taxonomy aliases.
    Famous/study puzzles already have canonical themes; append the 'famous'
    pseudo-theme so they surface as a category on the dashboard.
    """
    for p in puzzles:
        if p.origin_kind == "lichess":
            p.themes = tax.canonical(p.lichess_themes)
        elif p.origin_kind == "famous":
            # Keep author-supplied themes, then add 'famous' at the end if
            # the taxonomy has it declared.
            if "famous" in tax.by_id and "famous" not in p.themes:
                p.themes = list(p.themes) + ["famous"]
        # Drop puzzles with zero recognized themes — they carry no teaching signal.
    return [p for p in puzzles if p.themes]
