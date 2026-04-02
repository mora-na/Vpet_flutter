#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image


FRAMES_ROOT = Path(__file__).resolve().parents[1] / "assets" / "mu" / "frames"


def largest_alpha_component_mask(alpha: Image.Image) -> set[tuple[int, int]]:
  w, h = alpha.size
  pix = alpha.load()
  visited = [[False] * w for _ in range(h)]
  best: set[tuple[int, int]] = set()

  for y in range(h):
    for x in range(w):
      if visited[y][x] or pix[x, y] == 0:
        continue
      comp: set[tuple[int, int]] = set()
      q: deque[tuple[int, int]] = deque([(x, y)])
      visited[y][x] = True
      while q:
        cx, cy = q.popleft()
        comp.add((cx, cy))
        for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
          if nx < 0 or ny < 0 or nx >= w or ny >= h:
            continue
          if visited[ny][nx] or pix[nx, ny] == 0:
            continue
          visited[ny][nx] = True
          q.append((nx, ny))
      if len(comp) > len(best):
        best = comp
  return best


def process(path: Path) -> tuple[int, int]:
  img = Image.open(path).convert("RGBA")
  alpha = img.split()[-1]
  keep = largest_alpha_component_mask(alpha)
  if not keep:
    return (0, 0)

  pix = img.load()
  w, h = img.size
  total_opaque_before = 0
  removed = 0
  for y in range(h):
    for x in range(w):
      r, g, b, a = pix[x, y]
      if a == 0:
        continue
      total_opaque_before += 1
      if (x, y) not in keep:
        pix[x, y] = (r, g, b, 0)
        removed += 1
  img.save(path)
  return (removed, total_opaque_before - removed)


def main() -> None:
  files = sorted(FRAMES_ROOT.rglob("*.png"))
  if not files:
    raise SystemExit(f"no png files in {FRAMES_ROOT}")

  total_removed = 0
  for path in files:
    removed, remain = process(path)
    total_removed += removed
    print(f"{path.relative_to(FRAMES_ROOT)} removed={removed} remaining={remain}")
  print(f"done files={len(files)} totalRemoved={total_removed}")


if __name__ == "__main__":
  main()
