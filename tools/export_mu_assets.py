#!/usr/bin/env python3
import json
import os
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DST = ROOT / "assets" / "mu"
FRAMES_DST = DST / "frames"
DEFAULT_VPET_ROOTS = [
    ROOT.parent,
    Path("/Users/angelabeini/Desktop/lumu/VPet"),
]

FILENAME_PATTERN = re.compile(r"_(\d+)_(\d+)\.png$", re.IGNORECASE)


def parse_frame_meta(path: Path) -> tuple[int, int]:
    match = FILENAME_PATTERN.search(path.name)
    if not match:
        return (0, 125)
    return (int(match.group(1)), int(match.group(2)))


def collect_sorted_pngs(folder: Path) -> list[Path]:
    if not folder.exists():
        return []
    files = [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ".png"]
    return sorted(files, key=parse_frame_meta)


def find_vpet_root() -> Path:
    env_root = os.environ.get("VPET_ROOT")
    candidates = []
    if env_root:
        candidates.append(Path(env_root))
    candidates.extend(DEFAULT_VPET_ROOTS)
    for base in candidates:
        if (base / "VPet-Simulator.Windows" / "mod" / "0000_core" / "pet" / "Mu.lps").exists():
            return base
    raise FileNotFoundError("Cannot locate VPet root. Set VPET_ROOT to your VPet repo path.")


def parse_lps_pairs(line: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, value in re.findall(r"([A-Za-z0-9_]+)#([^:|]*)", line):
        result[key] = value
    return result


def parse_mu_lps(mu_lps_path: Path) -> dict:
    config = {
        "canvasSize": {"width": 500, "height": 500},
        "touchZones": {},
        "duration": {},
        "moveGraphs": [],
    }
    if not mu_lps_path.exists():
        return config

    lines = mu_lps_path.read_text(encoding="utf-8").splitlines()
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        lower = line.lower()
        if lower.startswith("touchhead:|"):
            pairs = parse_lps_pairs(line)
            config["touchZones"]["head"] = {
                "x": int(float(pairs.get("px", "0"))),
                "y": int(float(pairs.get("py", "0"))),
                "w": int(float(pairs.get("sw", "0"))),
                "h": int(float(pairs.get("sh", "0"))),
            }
        elif lower.startswith("touchbody:|"):
            pairs = parse_lps_pairs(line)
            config["touchZones"]["body"] = {
                "x": int(float(pairs.get("px", "0"))),
                "y": int(float(pairs.get("py", "0"))),
                "w": int(float(pairs.get("sw", "0"))),
                "h": int(float(pairs.get("sh", "0"))),
            }
        elif lower.startswith("pinch:|"):
            pairs = parse_lps_pairs(line)
            config["touchZones"]["pinch"] = {
                "x": int(float(pairs.get("px", "0"))),
                "y": int(float(pairs.get("py", "0"))),
                "w": int(float(pairs.get("sw", "0"))),
                "h": int(float(pairs.get("sh", "0"))),
            }
        elif lower.startswith("duration:|"):
            config["duration"] = parse_lps_pairs(line)
        elif lower.startswith("move:|"):
            pairs = parse_lps_pairs(line)
            graph = pairs.get("graph")
            if graph and graph not in config["moveGraphs"]:
                config["moveGraphs"].append(graph)
    return config


def copy_action(action: str, source_files: list[Path]) -> list[dict]:
    out_dir = FRAMES_DST / action
    out_dir.mkdir(parents=True, exist_ok=True)
    frames = []
    for idx, src in enumerate(source_files):
        _, duration = parse_frame_meta(src)
        out_name = f"{action}_{idx:03d}_{duration}.png"
        dst = out_dir / out_name
        shutil.copyfile(src, dst)
        frames.append(
            {
                "asset": f"assets/mu/frames/{action}/{out_name}",
                "durationMs": duration,
            }
        )
    return frames


def main() -> None:
    FRAMES_DST.mkdir(parents=True, exist_ok=True)
    vpet_root = find_vpet_root()
    src = vpet_root / "VPet-Simulator.Windows" / "mod" / "0000_core" / "pet" / "Mu"
    mu_lps = vpet_root / "VPet-Simulator.Windows" / "mod" / "0000_core" / "pet" / "Mu.lps"
    config = parse_mu_lps(mu_lps)

    default_src = collect_sorted_pngs(src / "Default" / "Nomal" / "1")
    move_src = (
        collect_sorted_pngs(src / "MOVE" / "walk.right" / "A_Nomal")
        + collect_sorted_pngs(src / "MOVE" / "walk.right" / "B_Nomal")
        + collect_sorted_pngs(src / "MOVE" / "walk.right" / "C_Nomal")
    )
    sleep_src = collect_sorted_pngs(src / "Sleep" / "B_Nomal")

    manifest = {
        "characters": {
            "mu": {
                "config": config,
                "actions": {
                    "default": copy_action("default", default_src),
                    "move": copy_action("move", move_src),
                    "sleep": copy_action("sleep", sleep_src),
                }
            }
        }
    }

    (DST / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print("export complete")
    print(f"default: {len(manifest['characters']['mu']['actions']['default'])} frames")
    print(f"move: {len(manifest['characters']['mu']['actions']['move'])} frames")
    print(f"sleep: {len(manifest['characters']['mu']['actions']['sleep'])} frames")


if __name__ == "__main__":
    main()
