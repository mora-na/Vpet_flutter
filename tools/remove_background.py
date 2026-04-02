#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image


FRAMES_ROOT = Path(__file__).resolve().parents[1] / "assets" / "mu" / "frames"

# Only flood from border pixels that are both opaque and dark.
# This removes dark backdrop connected to edges while preserving dark interior details.
ALPHA_MIN = 120
LUMA_MAX = 52


def is_dark_opaque(px: tuple[int, int, int, int]) -> bool:
    r, g, b, a = px
    if a < ALPHA_MIN:
        return False
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return luma <= LUMA_MAX


def strip_edge_connected_dark_background(path: Path) -> tuple[int, int]:
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    pix = img.load()

    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()

    def push_if_bg(x: int, y: int) -> None:
        if (x, y) in visited:
            return
        if is_dark_opaque(pix[x, y]):
            visited.add((x, y))
            queue.append((x, y))

    for x in range(w):
        push_if_bg(x, 0)
        push_if_bg(x, h - 1)
    for y in range(h):
        push_if_bg(0, y)
        push_if_bg(w - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            if (nx, ny) in visited:
                continue
            if is_dark_opaque(pix[nx, ny]):
                visited.add((nx, ny))
                queue.append((nx, ny))

    removed = len(visited)
    if removed == 0:
        return (0, sum(1 for *_, a in img.getdata() if a > 0))

    for x, y in visited:
        r, g, b, _ = pix[x, y]
        pix[x, y] = (r, g, b, 0)

    img.save(path)
    remaining = sum(1 for *_, a in img.getdata() if a > 0)
    return (removed, remaining)


def main() -> None:
    if not FRAMES_ROOT.exists():
        raise SystemExit(f"Frames folder not found: {FRAMES_ROOT}")

    files = sorted(FRAMES_ROOT.rglob("*.png"))
    if not files:
        raise SystemExit(f"No png files found under: {FRAMES_ROOT}")

    total_removed = 0
    for path in files:
        removed, remaining = strip_edge_connected_dark_background(path)
        total_removed += removed
        print(f"{path.relative_to(FRAMES_ROOT)} removed={removed} remainingOpaque={remaining}")

    print(f"done: files={len(files)} totalRemoved={total_removed}")


if __name__ == "__main__":
    main()
