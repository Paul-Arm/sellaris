"""Forge ship set — machine / industrial intelligence. Hexagonal segmented
hulls following assets/icons/fleet/fleet_construction_*.svg (amber hexagon,
#f2c14e) and fleet_raider shards (#ff8c3a). Dark iron plating, exposed spine
trusses, radiator fin banks, deliberately asymmetric antenna pods, and a single
heavy ember-glowing main engine per ship.

Ships face +X, up is +Z. Combat tiers grow via added hull segments, radiator
banks and truss length. Some asymmetry (an off-axis antenna, an extra pod) is
part of the machine aesthetic — it is placed deliberately, not randomly.
"""

import math

from shipgen_lib import (
    Palette,
    profile_diamond,
    profile_hex,
)

PALETTE = Palette(
    hull=(0.34, 0.35, 0.39),
    hull_b=(0.16, 0.16, 0.19),
    dark=(0.08, 0.08, 0.10),
    accent=(0.95, 0.76, 0.31),          # construction icon amber #f2c14e
    metal=(0.60, 0.44, 0.30),           # copper machinery
    engine_glow=(1.00, 0.55, 0.23),     # ember orange
    window_glow=(0.98, 0.78, 0.42),
    accent_glow=(1.00, 0.62, 0.24),
    roughness_hull=0.70,
    roughness_metal=0.40,
    panel_contrast=0.16,
    grime=0.12,
)

PREVIEW_ACCENT = (1.0, 0.6, 0.3)


def _offset(profile, dy=0.0, dz=0.0):
    return [(y + dy, z + dz) for (y, z) in profile]


def _hex_segment(b, x0, x1, r0, r1, region="hull_a", squash=0.78, taper_ends=True):
    """A single stepped hexagonal hull segment (prism with flat hex ends)."""
    b.loft(
        [
            (x0, profile_hex(r0 * 2, r0 * 2 * squash)),
            (x1, profile_hex(r1 * 2, r1 * 2 * squash)),
        ],
        region=region,
        cap_nose=taper_ends,
        cap_tail=taper_ends,
    )


def _truss(b, x0, x1, z, half=0.05, region="metal"):
    """Thin exposed spine truss (elongated hex beam)."""
    b.loft(
        [
            (x0, _offset(profile_hex(half * 2, half * 2), dz=z)),
            (x1, _offset(profile_hex(half * 2, half * 2), dz=z)),
        ],
        region=region,
        cap_nose=True,
        cap_tail=True,
    )


def _radiator_bank(b, x_center, count, length, height, y_off, z, region="accent",
                   spacing=0.12, glow=True):
    """Row of radiator fins (copper vanes over a glowing amber back-plane) on a
    flank. Fins stand proud of the hull so the bank reads as machinery."""
    # glowing back-plane first (so fins overlay it)
    if glow:
        span = count * spacing
        plate = [(x_center + span * 0.5, 0.02), (x_center + span * 0.55, height * 1.05),
                 (x_center - span * 0.55, height * 1.05), (x_center - span * 0.5, 0.02)]
        b.wing(plate, thickness=0.02, z=z, region=region, taper=1.0, plane="xz")
    for i in range(count):
        xf = x_center + (i - (count - 1) * 0.5) * spacing
        fin = [(xf + length * 0.5, 0.02), (xf + length * 0.42, height * 1.15),
               (xf - length * 0.5, height * 1.15), (xf - length * 0.42, 0.02)]
        b.wing(fin, thickness=0.03, z=z + 0.04, region="metal", taper=1.0, plane="xz")


def _main_engine(b, x, radius, z=0.0, verniers=True):
    """Single heavy engine bell + ember core, optional small vernier ring."""
    center = (x, 0.0, z)
    b.lathe(
        [(0.22, radius * 0.55), (0.05, radius), (-0.10, radius * 1.15), (-0.24, radius * 0.9)],
        segments=8, center=center, axis="X", region="hull_b", smooth=False)
    b.lathe(
        [(-0.20, radius * 0.95), (-0.30, radius * 0.05)],
        segments=8, center=center, axis="X", region="engine", smooth=True, close=False)
    if verniers:
        for i in range(4):
            a = i * math.tau / 4 + math.pi / 4
            vy = math.cos(a) * radius * 1.05
            vz = z + math.sin(a) * radius * 1.05
            b.lathe(
                [(0.05, radius * 0.16), (-0.10, radius * 0.20), (-0.16, radius * 0.05)],
                segments=6, center=(x + 0.12, vy, vz), axis="X",
                region="engine", smooth=True, close=True)


def _antenna(b, x, y, z, length, region="metal"):
    """Off-axis antenna mast with a glowing tip (deliberate asymmetry)."""
    b.loft(
        [
            (x, _offset(profile_diamond(0.05, 0.05), dy=y, dz=z)),
            (x - length * 0.15, _offset(profile_diamond(0.03, 0.03), dy=y, dz=z + length)),
        ],
        region=region,
        nose_point=(x - length * 0.18, y, z + length + 0.06),
        cap_tail=True,
    )
    b.lathe([(0.05, 0.0), (0.0, 0.045), (-0.05, 0.0)], segments=6,
            center=(x - length * 0.16, y, z + length), axis="Z", region="glow", smooth=True)


def build_corvette(b):
    """Compact hex drone with forward claw prongs and a single engine."""
    _hex_segment(b, -0.70, 0.35, 0.34, 0.40, region="hull_a")
    _hex_segment(b, 0.35, 0.95, 0.40, 0.22, region="hull_b")
    # armored prow cap
    b.loft(
        [(0.95, profile_hex(0.44, 0.34)), (1.20, profile_hex(0.26, 0.20))],
        region="hull_a", nose_point=(1.55, 0.0, 0.0), cap_tail=False)

    # --- forward claw prongs (asymmetric: 2 upper, 1 lower)
    for side in (-1.0, 1.0):
        claw = [(1.05, side * 0.20), (1.65, side * 0.34), (1.80, side * 0.28),
                (1.55, side * 0.18), (1.10, side * 0.12)]
        b.wing(claw, thickness=0.09, z=0.10, region="metal", taper=0.85)
    lower_claw = [(1.05, 0.0), (1.70, 0.05), (1.82, 0.0), (1.70, -0.05)]
    b.wing(lower_claw, thickness=0.08, z=-0.18, region="metal", taper=0.85)

    # --- dorsal accent ridge + amber strip
    b.loft(
        [(-0.55, _offset(profile_diamond(0.14, 0.09), dz=0.30)),
         (0.20, _offset(profile_diamond(0.18, 0.11), dz=0.34))],
        region="accent",
        nose_point=(0.70, 0.0, 0.24),
        tail_point=(-0.80, 0.0, 0.24),
    )
    # --- side radiator fins
    for side in (-1.0, 1.0):
        _radiator_bank(b, -0.25, 3, 0.42, 0.26, side, side * 0.42, region="glow")

    # --- off-axis antenna (asymmetry)
    _antenna(b, -0.30, 0.24, 0.28, 0.42)

    # --- exposed truss + single engine
    _truss(b, -0.95, -0.60, 0.0, half=0.09, region="hull_b")
    _main_engine(b, -0.92, 0.26, verniers=False)

    # --- forward sensor windows
    b.loft(
        [(0.55, _offset(profile_hex(0.20, 0.10), dz=0.16)),
         (0.85, _offset(profile_hex(0.14, 0.07), dz=0.14))],
        region="windows", cap_nose=True, cap_tail=True)

    b.scale_axis(0.90)  # length target ~2.7


def build_destroyer(b):
    """Spine truss joins an armored hex prow to an engine block; side radiators."""
    # --- armored forward hex hull
    _hex_segment(b, 0.10, 0.95, 0.46, 0.30, region="hull_a")
    b.loft(
        [(0.95, profile_hex(0.60, 0.46)), (1.25, profile_hex(0.34, 0.26))],
        region="hull_a", nose_point=(1.75, 0.0, 0.02), cap_tail=False)
    # --- aft engine block (bigger hex)
    _hex_segment(b, -1.75, -0.85, 0.44, 0.52, region="hull_b")

    # --- exposed spine trusses connecting prow to block
    for dz in (0.14, -0.14):
        _truss(b, -0.95, 0.20, dz, half=0.07, region="metal")
    _truss(b, -0.9, 0.15, 0.0, half=0.09, region="hull_b")

    # --- forward gun claws
    for side in (-1.0, 1.0):
        claw = [(1.05, side * 0.26), (1.80, side * 0.40), (1.98, side * 0.32),
                (1.70, side * 0.20), (1.10, side * 0.14)]
        b.wing(claw, thickness=0.10, z=0.06, region="metal", taper=0.85)

    # --- dorsal amber ridge
    b.loft(
        [(-1.55, _offset(profile_diamond(0.14, 0.10), dz=0.40)),
         (-1.05, _offset(profile_diamond(0.20, 0.13), dz=0.44)),
         (0.55, _offset(profile_diamond(0.16, 0.11), dz=0.30))],
        region="accent",
        nose_point=(0.95, 0.0, 0.24),
        tail_point=(-1.80, 0.0, 0.30),
    )

    # --- side radiator banks (larger)
    for side in (-1.0, 1.0):
        _radiator_bank(b, -0.5, 4, 0.5, 0.34, side, side * 0.5, region="glow")
    # --- asymmetric antennas
    _antenna(b, -0.4, 0.30, 0.36, 0.55)
    _antenna(b, -0.1, -0.34, 0.20, 0.38)

    # --- heavy engine
    _main_engine(b, -1.78, 0.40)

    # --- bridge windows
    b.loft(
        [(0.30, _offset(profile_hex(0.24, 0.12), dz=0.22)),
         (0.70, _offset(profile_hex(0.16, 0.09), dz=0.20))],
        region="windows", cap_nose=True, cap_tail=True)

    b.scale_axis(0.89)  # length target ~3.6


def build_cruiser(b):
    """Triple parallel hex hulls bridged by trusses; twin radiator wings."""
    # --- central primary hull
    _hex_segment(b, -1.30, 0.70, 0.50, 0.58, region="hull_a")
    b.loft(
        [(0.70, profile_hex(0.68, 0.52)), (1.15, profile_hex(0.40, 0.30))],
        region="hull_a", nose_point=(1.95, 0.0, 0.02), cap_tail=False)
    b.loft(
        [(-1.30, profile_hex(0.58, 0.44)), (-1.65, profile_hex(0.40, 0.30))],
        region="hull_b", tail_point=(-1.95, 0.0, 0.0), cap_nose=False)

    # --- two outboard hex hulls
    for side in (-1.0, 1.0):
        y = side * 0.82
        b.loft(
            [(-1.05, _offset(profile_hex(0.30, 0.26), dy=y)),
             (-0.30, _offset(profile_hex(0.36, 0.30), dy=y)),
             (0.55, _offset(profile_hex(0.28, 0.24), dy=y))],
            region="hull_b",
            nose_point=(1.15, y, 0.0),
            tail_point=(-1.45, y, 0.0),
        )
        # bridging trusses
        _truss(b, -0.8, 0.4, 0.0, half=0.05, region="metal")
        for xb in (-0.7, 0.0, 0.5):
            b.loft(
                [(xb, _offset(profile_hex(0.05, 0.05), dy=side * 0.30)),
                 (xb, _offset(profile_hex(0.05, 0.05), dy=side * 0.60))],
                region="metal", cap_nose=True, cap_tail=True)

    # --- dorsal amber spine
    b.loft(
        [(-1.20, _offset(profile_diamond(0.18, 0.12), dz=0.48)),
         (-0.20, _offset(profile_diamond(0.24, 0.15), dz=0.52)),
         (0.60, _offset(profile_diamond(0.18, 0.12), dz=0.44))],
        region="accent",
        nose_point=(1.10, 0.0, 0.34),
        tail_point=(-1.55, 0.0, 0.36),
    )

    # --- large radiator banks on the outboard hulls
    for side in (-1.0, 1.0):
        _radiator_bank(b, -0.3, 5, 0.55, 0.4, side, side * 1.12, region="glow")
    # --- asymmetric sensor mast cluster
    _antenna(b, -0.5, 0.0, 0.50, 0.7)
    _antenna(b, -0.2, 0.44, 0.30, 0.5)

    # --- twin engines (heavy center + smaller aft-offset)
    _main_engine(b, -1.68, 0.44)
    _main_engine(b, -1.45, 0.22, z=0.30, verniers=False)

    # --- bridge windows
    b.loft(
        [(0.10, _offset(profile_hex(0.30, 0.14), dz=0.30)),
         (0.60, _offset(profile_hex(0.20, 0.10), dz=0.26))],
        region="windows", cap_nose=True, cap_tail=True)

    b.scale_axis(1.24)  # length target ~4.8


def build_battleship(b):
    """Foundry dreadnought: glowing furnace maw, stacked radiator banks, trusses."""
    # --- massive central hull (stepped hex segments)
    _hex_segment(b, -2.20, -0.60, 0.66, 0.86, region="hull_a")
    _hex_segment(b, -0.60, 0.90, 0.86, 0.72, region="hull_b")
    b.loft(
        [(0.90, profile_hex(0.92, 0.70)), (1.45, profile_hex(0.60, 0.46))],
        region="hull_a", nose_point=(1.90, 0.0, 0.02), cap_tail=False)

    # --- forward furnace maw (recessed glowing intake in the prow)
    b.lathe(
        [(0.0, 0.44), (-0.22, 0.40), (-0.42, 0.30), (-0.55, 0.10)],
        segments=8, center=(1.55, 0.0, 0.0), axis="X", region="dark", smooth=False, close=False)
    b.lathe(
        [(-0.30, 0.34), (-0.50, 0.22), (-0.62, 0.03)],
        segments=8, center=(1.55, 0.0, 0.0), axis="X", region="engine", smooth=True, close=False)

    # --- aft engine cluster block
    _hex_segment(b, -2.75, -2.10, 0.60, 0.74, region="hull_b")

    # --- tiered dorsal superstructure
    b.loft(
        [(-1.70, _offset(profile_hex(0.50, 0.30), dz=0.62)),
         (-0.60, _offset(profile_hex(0.56, 0.34), dz=0.66)),
         (0.30, _offset(profile_hex(0.40, 0.26), dz=0.58))],
        region="hull_a",
        nose_point=(0.85, 0.0, 0.42),
        tail_point=(-2.10, 0.0, 0.46),
    )
    b.loft(
        [(-1.30, _offset(profile_diamond(0.26, 0.16), dz=0.92)),
         (-0.50, _offset(profile_diamond(0.32, 0.20), dz=0.98)),
         (0.05, _offset(profile_diamond(0.22, 0.14), dz=0.88))],
        region="accent",
        nose_point=(0.55, 0.0, 0.70),
        tail_point=(-1.70, 0.0, 0.74),
    )

    # --- twin radiator rows per side (parallel banks)
    for side in (-1.0, 1.0):
        _radiator_bank(b, -0.8, 6, 0.62, 0.46, side, side * 0.98, region="glow")
        _radiator_bank(b, -0.5, 5, 0.5, 0.36, side, side * 0.66, region="accent")

    # --- exposed lateral trusses + outboard engine pods
    for side in (-1.0, 1.0):
        y = side * 0.95
        b.loft(
            [(-2.55, _offset(profile_hex(0.26, 0.22), dy=y)),
             (-2.15, _offset(profile_hex(0.34, 0.28), dy=y)),
             (-1.70, _offset(profile_hex(0.26, 0.22), dy=y))],
            region="hull_b",
            nose_point=(-1.20, y, 0.0),
            cap_tail=True,
        )
        _truss(b, -2.2, -1.4, 0.0, half=0.06, region="metal")
        _main_engine(b, -2.62, 0.26, z=0.0, verniers=False)
        # place outboard engine at y via a shifted bell
        b.lathe(
            [(-0.10, 0.24), (-0.24, 0.02)],
            segments=8, center=(-2.62, y, 0.0), axis="X", region="engine", smooth=True, close=False)
        b.lathe(
            [(0.16, 0.14), (0.02, 0.26), (-0.12, 0.22)],
            segments=8, center=(-2.62, y, 0.0), axis="X", region="hull_b", smooth=False)

    # --- asymmetric antenna array
    _antenna(b, -0.9, 0.0, 1.02, 0.9)
    _antenna(b, -0.5, 0.60, 0.55, 0.65)
    _antenna(b, -1.3, -0.55, 0.60, 0.55)

    # --- heavy central engines
    _main_engine(b, -2.72, 0.56)

    # --- bridge windows
    b.loft(
        [(-0.30, _offset(profile_hex(0.34, 0.16), dz=0.98)),
         (0.15, _offset(profile_hex(0.24, 0.12), dz=0.90))],
        region="windows", cap_nose=True, cap_tail=True)

    b.scale_axis(1.28)  # length target ~6.3


def build_science(b):
    """Hex probe with a big lattice dish and an asymmetric antenna boom."""
    _hex_segment(b, -1.00, 0.45, 0.30, 0.36, region="hull_a")
    b.loft(
        [(0.45, profile_hex(0.40, 0.30)), (0.75, profile_hex(0.22, 0.16))],
        region="hull_b", nose_point=(1.20, 0.0, 0.0), cap_tail=False)

    # --- dorsal pylon + big lattice dish
    pylon = [(0.10, 0.10), (-0.35, 0.10), (-0.45, 0.42), (0.00, 0.42)]
    b.wing(pylon, thickness=0.09, z=0.0, region="hull_b", taper=0.9, plane="xz")
    dish_c = (-0.02, 0.0, 0.52)
    # dish rim (hex torus)
    b.lathe(
        [(0.04, 0.46), (0.0, 0.50), (-0.04, 0.46), (0.0, 0.42)],
        segments=8, center=dish_c, axis="X", region="metal", smooth=False, close=False)
    # dish face (shallow cone)
    b.lathe(
        [(0.06, 0.44), (-0.06, 0.26), (-0.14, 0.02)],
        segments=8, center=dish_c, axis="X", region="accent", smooth=True, close=False)
    # lattice spokes across the dish
    for i in range(3):
        a = i * math.pi / 3
        spoke = [(0.07, 0.0), (0.07, 0.44)]
        b.loft(
            [(dish_c[0] + 0.05, _offset(profile_diamond(0.03, 0.03), dy=math.cos(a) * 0.0, dz=0.52 + math.sin(a) * 0.0)),
             (dish_c[0] + 0.05, _offset(profile_diamond(0.03, 0.03), dy=math.cos(a) * 0.44, dz=0.52 + math.sin(a) * 0.44))],
            region="metal", cap_nose=True, cap_tail=True)
    # focal glow bead
    b.lathe([(0.10, 0.0), (0.05, 0.06), (0.0, 0.08)], segments=8,
            center=dish_c, axis="X", region="glow", smooth=True, close=True)

    # --- asymmetric instrument boom (one long side arm)
    boom = [(0.30, 0.30), (0.55, 0.95), (0.62, 0.98), (0.36, 0.32)]
    b.wing(boom, thickness=0.05, z=0.05, region="metal", taper=1.0)
    b.lathe([(0.0, 0.05), (0.10, 0.0)], segments=6,
            center=(0.58, 0.96, 0.05), axis="X", region="glow", smooth=True)
    _antenna(b, -0.3, -0.30, 0.24, 0.5)

    # --- side radiators + engine
    for side in (-1.0, 1.0):
        _radiator_bank(b, -0.35, 3, 0.36, 0.24, side, side * 0.34, region="glow")
    _main_engine(b, -1.05, 0.24, verniers=False)

    b.loft(
        [(0.15, _offset(profile_hex(0.18, 0.09), dz=0.14)),
         (0.45, _offset(profile_hex(0.12, 0.06), dz=0.12))],
        region="windows", cap_nose=True, cap_tail=True)


def build_builder(b):
    """Industrial tug: asymmetric crane arm, hex cargo pods, exposed machinery."""
    _hex_segment(b, -0.85, 0.35, 0.42, 0.46, region="hull_a", squash=0.9)
    b.loft(
        [(0.35, profile_hex(0.52, 0.46)), (0.70, profile_hex(0.30, 0.26))],
        region="hull_b", nose_point=(1.05, 0.0, 0.0), cap_tail=False)

    # --- asymmetric forward crane arm (long, one side, articulated)
    crane1 = [(0.70, 0.10), (1.35, 0.16), (1.42, 0.24), (0.75, 0.20)]
    b.wing(crane1, thickness=0.10, z=0.30, region="metal", taper=0.9)
    crane2 = [(1.30, 0.14), (1.75, 0.02), (1.80, 0.10), (1.36, 0.24)]
    b.wing(crane2, thickness=0.09, z=0.30, region="metal", taper=0.9)
    # claw tip
    b.lathe([(0.10, 0.0), (0.0, 0.09), (-0.08, 0.05)], segments=6,
            center=(1.76, 0.06, 0.30), axis="X", region="glow", smooth=True)

    # --- side cargo hex pods (asymmetric: 2 left, 1 right)
    for (y, x0) in [(-0.60, -0.55), (-0.60, 0.05), (0.60, -0.25)]:
        b.loft(
            [(x0 - 0.30, _offset(profile_hex(0.24, 0.24), dy=y)),
             (x0, _offset(profile_hex(0.30, 0.30), dy=y)),
             (x0 + 0.30, _offset(profile_hex(0.22, 0.22), dy=y))],
            region="hull_b",
            nose_point=(x0 + 0.45, y, 0.0),
            tail_point=(x0 - 0.45, y, 0.0),
        )
    # exposed machinery greeble strip
    strip = [(0.20, 0.05), (-0.75, 0.09), (-0.75, -0.10), (0.20, -0.06)]
    b.wing(strip, thickness=0.06, z=0.44, region="greeble", taper=1.0, plane="xz")

    # --- amber ridge + antenna + engine
    b.loft(
        [(-0.60, _offset(profile_diamond(0.14, 0.10), dz=0.36)),
         (0.15, _offset(profile_diamond(0.18, 0.12), dz=0.38))],
        region="accent",
        nose_point=(0.55, 0.0, 0.28),
        tail_point=(-0.85, 0.0, 0.28),
    )
    _antenna(b, -0.4, 0.34, 0.30, 0.42)
    _main_engine(b, -0.88, 0.34, verniers=False)


def build_station(b):
    """Hexagonal ring station around a central spindle — the construction icon."""
    # --- central spindle (stacked hex drums), axis Z
    for i, (z0, z1, r0, r1, reg) in enumerate([
        (-0.30, 0.35, 0.55, 0.60, "hull_a"),
        (0.35, 1.05, 0.60, 0.42, "hull_b"),
        (1.05, 1.55, 0.42, 0.24, "hull_a"),
    ]):
        b.lathe(
            [(0.0, r0), (z1 - z0, r1)],
            segments=6, center=(0.0, 0.0, z0), axis="Z",
            region=reg, smooth=False, close=(i == 0))
    # crown beacon
    b.lathe([(0.0, 0.24), (0.14, 0.12), (0.26, 0.0)], segments=6,
            center=(0.0, 0.0, 1.55), axis="Z", region="accent", smooth=False, close=False)

    # --- the big hexagonal habitat ring (construction icon hexagon)
    ring_r = 1.85
    b.lathe(
        [(-0.18, ring_r), (0.0, ring_r + 0.20), (0.18, ring_r), (0.0, ring_r - 0.14)],
        segments=6, center=(0.0, 0.0, 0.35), axis="Z", region="hull_a", smooth=False, close=False)
    # glowing amber inner band on the ring
    b.lathe(
        [(-0.06, ring_r - 0.08), (0.0, ring_r - 0.02), (0.06, ring_r - 0.08)],
        segments=6, center=(0.0, 0.0, 0.35), axis="Z", region="glow", smooth=False, close=False)

    # --- six radial spoke trusses connecting spindle to ring
    for i in range(6):
        ang = i * math.tau / 6
        c, s = math.cos(ang), math.sin(ang)
        spoke = [(0.55, 0.06), (ring_r, 0.06), (ring_r, -0.06), (0.55, -0.06)]
        rot = [(x * c - y * s, x * s + y * c) for (x, y) in spoke]
        b.wing(rot, thickness=0.12, z=0.35, region="metal", taper=0.85)
        # radiator fin on alternating spokes
        if i % 2 == 0:
            rad = [(ring_r * 0.55, 0.0), (ring_r * 0.55, 0.34), (ring_r * 0.8, 0.34), (ring_r * 0.8, 0.0)]
            rrot = [(x * c - y * s, x * s + y * c) for (x, y) in rad]
            b.wing(rrot, thickness=0.03, z=0.6, region="accent", taper=1.0)


def build_stellar_station(b):
    """Grand foundry: double hex ring, radial trusses, furnace-glow core."""
    # --- taller central spindle
    for i, (z0, z1, r0, r1, reg) in enumerate([
        (-0.45, 0.40, 0.80, 0.86, "hull_a"),
        (0.40, 1.30, 0.86, 0.60, "hull_b"),
        (1.30, 2.05, 0.60, 0.34, "hull_a"),
    ]):
        b.lathe(
            [(0.0, r0), (z1 - z0, r1)],
            segments=6, center=(0.0, 0.0, z0), axis="Z",
            region=reg, smooth=False, close=(i == 0))
    # furnace-glow core band
    b.lathe(
        [(-0.20, 0.88), (0.0, 0.98), (0.20, 0.88), (0.0, 0.80)],
        segments=6, center=(0.0, 0.0, 0.40), axis="Z", region="engine", smooth=False, close=False)
    b.lathe([(0.0, 0.34), (0.20, 0.16), (0.36, 0.0)], segments=6,
            center=(0.0, 0.0, 2.05), axis="Z", region="accent", smooth=False, close=False)

    # --- two concentric hex habitat rings at different heights
    for (ring_r, z, reg) in [(2.60, 0.30, "hull_a"), (1.90, 1.20, "hull_b")]:
        b.lathe(
            [(-0.22, ring_r), (0.0, ring_r + 0.24), (0.22, ring_r), (0.0, ring_r - 0.16)],
            segments=6, center=(0.0, 0.0, z), axis="Z", region=reg, smooth=False, close=False)
        b.lathe(
            [(-0.07, ring_r - 0.10), (0.0, ring_r - 0.02), (0.07, ring_r - 0.10)],
            segments=6, center=(0.0, 0.0, z), axis="Z", region="glow", smooth=False, close=False)

    # --- radial spoke trusses to the lower ring
    for i in range(6):
        ang = i * math.tau / 6
        c, s = math.cos(ang), math.sin(ang)
        spoke = [(0.80, 0.08), (2.60, 0.08), (2.60, -0.08), (0.80, -0.08)]
        rot = [(x * c - y * s, x * s + y * c) for (x, y) in spoke]
        b.wing(rot, thickness=0.14, z=0.30, region="metal", taper=0.85)
        # radiator banks on alternating spokes
        if i % 2 == 0:
            rad = [(1.3, 0.0), (1.3, 0.5), (1.9, 0.5), (1.9, 0.0)]
            rrot = [(x * c - y * s, x * s + y * c) for (x, y) in rad]
            b.wing(rrot, thickness=0.04, z=0.62, region="accent", taper=1.0)
    # upper ring spokes (offset)
    for i in range(6):
        ang = i * math.tau / 6 + math.pi / 6
        c, s = math.cos(ang), math.sin(ang)
        spoke = [(0.65, 0.06), (1.90, 0.06), (1.90, -0.06), (0.65, -0.06)]
        rot = [(x * c - y * s, x * s + y * c) for (x, y) in spoke]
        b.wing(rot, thickness=0.10, z=1.20, region="metal", taper=0.85)


BUILDERS = {
    "corvette": build_corvette,
    "destroyer": build_destroyer,
    "cruiser": build_cruiser,
    "battleship": build_battleship,
    "science": build_science,
    "builder": build_builder,
    "station": build_station,
    "stellar_station": build_stellar_station,
}

BUDGETS = {
    "corvette": 950,
    "destroyer": 1400,
    "cruiser": 1900,
    "battleship": 2800,
    "science": 1100,
    "builder": 1100,
    "station": 2200,
    "stellar_station": 3000,
}
