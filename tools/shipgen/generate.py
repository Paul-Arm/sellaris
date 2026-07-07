"""Headless Blender entry point for ship set generation.

Run from the repo root:
  & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" \
      --background --factory-startup --python tools/shipgen/generate.py -- \
      --set vanguard --out assets/ships/vanguard --preview <dir>

A set module (tools/shipgen/sets/<id>.py) must expose:
  PALETTE:  shipgen_lib.Palette
  BUILDERS: dict visual_key -> fn(builder: ShipBuilder) building the geometry
  BUDGETS:  optional dict visual_key -> max tri count
  PREVIEW_ACCENT: optional (r, g, b) fill light color for preview renders
"""

import argparse
import importlib
import json
import os
import random
import sys
import zlib

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import shipgen_lib as lib  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", dest="set_id", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--preview", default="")
    parser.add_argument("--atlas-size", type=int, default=lib.ATLAS_SIZE)
    parser.add_argument("--no-render", action="store_true")
    args = parser.parse_args(argv)

    lib.reset_scene()
    set_module = importlib.import_module(f"sets.{args.set_id}")

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    seed = zlib.crc32(args.set_id.encode())

    print(f"[shipgen] painting atlas for '{args.set_id}' ({args.atlas_size}px)")
    arrays = lib.paint_atlas(set_module.PALETTE, seed=seed, size=args.atlas_size)
    images = {
        "albedo": lib.save_image(f"{args.set_id}_albedo", arrays["albedo"], out_dir, srgb=True),
        "emission": lib.save_image(f"{args.set_id}_emission", arrays["emission"], out_dir, srgb=True),
        "orm": lib.save_image(f"{args.set_id}_orm", arrays["orm"], out_dir, srgb=False),
    }
    material = lib.build_material(args.set_id, images)

    budgets = getattr(set_module, "BUDGETS", {})
    objects = []
    stats = {}
    failures = []
    for visual_key, builder_fn in set_module.BUILDERS.items():
        print(f"[shipgen] building '{visual_key}'")
        builder = lib.ShipBuilder(visual_key, rng=random.Random(f"{args.set_id}:{visual_key}"))
        builder_fn(builder)
        obj = builder.commit(material)
        tris = lib.tri_count(obj)
        dims = [round(v, 3) for v in obj.dimensions]
        stats[visual_key] = {"tris": tris, "dims": dims}
        budget = budgets.get(visual_key)
        if budget and tris > budget:
            failures.append(f"{visual_key}: {tris} tris exceeds budget {budget}")
        objects.append(obj)

    glb_path = os.path.join(out_dir, f"{args.set_id}_ships.glb")
    lib.export_glb(objects, glb_path)
    stats["_glb"] = {"path": glb_path, "bytes": os.path.getsize(glb_path)}

    sheet_path = ""
    if args.preview and not args.no_render:
        preview_dir = os.path.abspath(args.preview)
        os.makedirs(preview_dir, exist_ok=True)
        accent = getattr(set_module, "PREVIEW_ACCENT", (0.8, 0.85, 1.0))
        print(f"[shipgen] rendering previews to {preview_dir}")
        sheet_path = lib.render_previews(objects, preview_dir, args.set_id, accent=accent)
        stats["_preview"] = {"contact_sheet": sheet_path}

    stats_path = os.path.join(out_dir, f"{args.set_id}_stats.json")
    with open(stats_path, "w", encoding="utf-8") as handle:
        json.dump(stats, handle, indent=2)

    print(f"[shipgen] === {args.set_id} summary ===")
    for key, entry in stats.items():
        if key.startswith("_"):
            continue
        print(f"[shipgen]   {key}: {entry['tris']} tris, dims {entry['dims']}")
    print(f"[shipgen] glb: {glb_path} ({stats['_glb']['bytes'] // 1024} KiB)")
    if sheet_path:
        print(f"[shipgen] contact sheet: {sheet_path}")
    if failures:
        for failure in failures:
            print(f"[shipgen] BUDGET FAIL {failure}")
        sys.exit(2)
    print("[shipgen] done")


if __name__ == "__main__":
    main()
