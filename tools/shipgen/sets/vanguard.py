"""Vanguard ship set — angular human military. Dart / chevron silhouettes
following assets/icons/fleet/fleet_attack_*.svg, gunmetal hull with red
accent panels (#e85050) and cyan-white engines.

Ships face +X, up is +Z. Corvette is ~2.7 units long; combat tiers grow from
there (destroyer ~3.6, cruiser ~4.8, battleship ~6.4). Stations are vertical
faceted spindles with radial pad arms and octagonal habitat rings.
"""

import math

from shipgen_lib import (
    Palette,
    blend_profiles,
    profile_chine,
    profile_diamond,
    profile_hex,
)

PALETTE = Palette(
    hull=(0.58, 0.61, 0.66),
    hull_b=(0.38, 0.41, 0.47),
    dark=(0.13, 0.14, 0.17),
    accent=(0.91, 0.31, 0.31),      # fleet icon red #e85050
    metal=(0.52, 0.53, 0.56),
    engine_glow=(0.55, 0.85, 1.00),
    window_glow=(1.00, 0.93, 0.78),
    accent_glow=(1.00, 0.42, 0.36),
    roughness_hull=0.58,
    panel_contrast=0.10,
    grime=0.07,
)

PREVIEW_ACCENT = (1.0, 0.55, 0.5)


def _offset(profile, dy=0.0, dz=0.0):
    return [(y + dy, z + dz) for (y, z) in profile]


def _rot_xy(points, angle_deg):
    """Rotate a 2D outline around the origin (for radial station arms)."""
    a = math.radians(angle_deg)
    c, s = math.cos(a), math.sin(a)
    return [(x * c - y * s, x * s + y * c) for (x, y) in points]


def _engine_pair(b, x, y_off, z, scale=1.0):
    """Twin lathed nozzles with glow cones at the exhaust."""
    for side in (-1.0, 1.0):
        center = (x, side * y_off, z)
        b.lathe(
            [(0.20 * scale, 0.055 * scale), (0.08 * scale, 0.105 * scale),
             (-0.05 * scale, 0.125 * scale), (-0.16 * scale, 0.095 * scale)],
            segments=10, center=center, axis="X", region="dark", smooth=True)
        b.lathe(
            [(-0.150 * scale, 0.085 * scale), (-0.185 * scale, 0.002)],
            segments=10, center=center, axis="X", region="engine",
            smooth=True, close=False)


def _oct_ring(b, z, r_mid, half, thick, region):
    """Octagonal habitat ring (torus with diamond cross section)."""
    b.lathe(
        [(-half, r_mid), (0.0, r_mid + thick), (half, r_mid),
         (0.0, r_mid - thick), (-half, r_mid)],
        segments=8, center=(0, 0, z), axis="Z", region=region,
        smooth=False, close=False)


def _gun_barrels(b, x, y_off, z, length=0.55, radius=0.022):
    for side in (-1.0, 1.0):
        b.lathe(
            [(0.0, radius), (length, radius * 0.68)],
            segments=6, center=(x, side * y_off, z), axis="X",
            region="metal", smooth=True, close=True)


def build_corvette(b):
    # --- main hull: faceted dart, chine profiles lofted nose-to-tail
    b.loft(
        [
            (-1.30, profile_chine(0.30, 0.16, chine=0.5)),
            (-1.00, profile_chine(0.46, 0.27, chine=0.45)),
            (-0.45, profile_chine(0.58, 0.31, chine=0.4)),
            (0.25, profile_chine(0.46, 0.25, chine=0.4)),
            (0.90, profile_chine(0.24, 0.14, chine=0.5)),
        ],
        region="hull_a",
        nose_point=(1.40, 0.0, 0.015),
        cap_tail=True,
    )

    # --- dorsal spine ridge (accent stripe like the icon dart)
    b.loft(
        [
            (-0.85, _offset(profile_diamond(0.10, 0.07), dz=0.16)),
            (-0.30, _offset(profile_diamond(0.17, 0.11), dz=0.19)),
            (0.35, _offset(profile_diamond(0.12, 0.08), dz=0.15)),
        ],
        region="accent",
        nose_point=(0.78, 0.0, 0.11),
        tail_point=(-1.05, 0.0, 0.12),
    )

    # --- swept dart wings with trailing notch (top view outline)
    wing_outline = [
        (0.18, 0.16), (-0.28, 0.30), (-0.98, 0.42), (-0.80, 0.78),
        (-1.12, 1.02), (-0.66, 0.96), (-0.30, 0.62), (0.02, 0.34),
    ]
    b.wing(wing_outline, thickness=0.055, z=-0.035, region="wing", taper=0.82)
    b.wing(wing_outline, thickness=0.055, z=-0.035, region="wing", taper=0.82, flip=True)

    # --- wingtip accent blades
    tip_outline = [(-0.70, 0.90), (-1.16, 1.06), (-0.98, 1.12), (-0.62, 1.00)]
    b.wing(tip_outline, thickness=0.07, z=-0.03, region="accent", taper=0.7)
    b.wing(tip_outline, thickness=0.07, z=-0.03, region="accent", taper=0.7, flip=True)

    # --- ventral keel fin (side view outline, vertical slab)
    keel_outline = [(0.05, -0.10), (-0.35, -0.16), (-0.85, -0.44), (-1.05, -0.40), (-0.75, -0.12)]
    b.wing(keel_outline, thickness=0.045, z=0.0, region="wing", taper=0.85, plane="xz")

    # --- flank machinery skirts (greeble texture strip)
    skirt = [(0.05, 0.05), (-0.95, 0.09), (-0.95, -0.10), (0.05, -0.07)]
    b.wing(skirt, thickness=0.05, z=0.265, region="greeble", taper=1.0, plane="xz")
    b.wing(skirt, thickness=0.05, z=-0.265, region="greeble", taper=1.0, plane="xz")

    # --- cockpit canopy (window glass strip)
    b.loft(
        [
            (0.42, _offset(profile_diamond(0.13, 0.05), dz=0.115)),
            (0.62, _offset(profile_diamond(0.10, 0.045), dz=0.105)),
        ],
        region="windows",
        nose_point=(0.86, 0.0, 0.07),
        tail_point=(0.30, 0.0, 0.10),
    )

    # --- engines
    _engine_pair(b, -1.28, 0.13, 0.01)


def build_destroyer(b):
    """Stretched corvette: raised forward gun spine + twin flank engine pods."""
    # --- main hull
    b.loft(
        [
            (-1.60, profile_chine(0.34, 0.18, chine=0.5)),
            (-1.20, profile_chine(0.52, 0.30, chine=0.45)),
            (-0.50, profile_chine(0.66, 0.35, chine=0.42)),
            (0.35, profile_chine(0.52, 0.28, chine=0.42)),
            (1.05, profile_chine(0.28, 0.16, chine=0.5)),
        ],
        region="hull_a",
        nose_point=(1.70, 0.0, 0.02),
        cap_tail=True,
    )

    # --- raised forward gun spine
    b.loft(
        [
            (-0.20, _offset(profile_chine(0.18, 0.11, chine=0.5), dz=0.21)),
            (0.40, _offset(profile_chine(0.22, 0.13, chine=0.5), dz=0.22)),
            (0.95, _offset(profile_chine(0.13, 0.09, chine=0.5), dz=0.18)),
        ],
        region="hull_a",
        nose_point=(1.30, 0.0, 0.12),
        tail_point=(-0.50, 0.0, 0.16),
    )
    _gun_barrels(b, 0.90, 0.085, 0.26, length=0.60, radius=0.024)

    # --- dorsal accent ridge aft of the spine
    b.loft(
        [
            (-1.15, _offset(profile_diamond(0.12, 0.08), dz=0.22)),
            (-0.55, _offset(profile_diamond(0.18, 0.12), dz=0.26)),
            (-0.10, _offset(profile_diamond(0.13, 0.09), dz=0.23)),
        ],
        region="accent",
        nose_point=(0.25, 0.0, 0.18),
        tail_point=(-1.40, 0.0, 0.16),
    )

    # --- swept dart wings with trailing notch
    wing_outline = [
        (0.30, 0.20), (-0.25, 0.36), (-1.10, 0.50), (-0.90, 0.88),
        (-1.30, 1.16), (-0.78, 1.08), (-0.35, 0.70), (0.10, 0.40),
    ]
    b.wing(wing_outline, thickness=0.06, z=-0.04, region="wing", taper=0.82)
    b.wing(wing_outline, thickness=0.06, z=-0.04, region="wing", taper=0.82, flip=True)
    tip_outline = [(-0.82, 1.02), (-1.34, 1.20), (-1.14, 1.28), (-0.72, 1.14)]
    b.wing(tip_outline, thickness=0.075, z=-0.035, region="accent", taper=0.7)
    b.wing(tip_outline, thickness=0.075, z=-0.035, region="accent", taper=0.7, flip=True)

    # --- ventral keel fin
    keel = [(0.10, -0.12), (-0.45, -0.20), (-1.00, -0.52), (-1.25, -0.47), (-0.85, -0.14)]
    b.wing(keel, thickness=0.05, z=0.0, region="wing", taper=0.85, plane="xz")

    # --- greeble flank skirts
    skirt = [(0.15, 0.06), (-1.10, 0.10), (-1.10, -0.12), (0.15, -0.08)]
    b.wing(skirt, thickness=0.05, z=0.30, region="greeble", taper=1.0, plane="xz")
    b.wing(skirt, thickness=0.05, z=-0.30, region="greeble", taper=1.0, plane="xz")

    # --- twin flank engine pods (faceted hex lofts) + nozzles
    for side in (-1.0, 1.0):
        y = side * 0.36
        b.loft(
            [
                (-1.72, _offset(profile_hex(0.17, 0.15), dy=y)),
                (-1.42, _offset(profile_hex(0.26, 0.22), dy=y)),
                (-0.95, _offset(profile_hex(0.21, 0.18), dy=y)),
            ],
            region="hull_b",
            nose_point=(-0.55, y, 0.0),
            cap_tail=True,
        )
    _engine_pair(b, -1.70, 0.36, 0.0, scale=1.25)

    # --- cockpit canopy
    b.loft(
        [
            (0.50, _offset(profile_diamond(0.15, 0.055), dz=0.145)),
            (0.80, _offset(profile_diamond(0.11, 0.05), dz=0.13)),
        ],
        region="windows",
        nose_point=(1.10, 0.0, 0.09),
        tail_point=(0.35, 0.0, 0.125),
    )


def build_cruiser(b):
    """Broad twin-hull cruiser: center dart + blended side hulls, layered decks."""
    # --- center hull
    b.loft(
        [
            (-2.25, profile_chine(0.40, 0.22, chine=0.5)),
            (-1.55, profile_chine(0.62, 0.34, chine=0.45)),
            (-0.50, profile_chine(0.74, 0.40, chine=0.42)),
            (0.60, profile_chine(0.58, 0.32, chine=0.42)),
            (1.55, profile_chine(0.30, 0.18, chine=0.5)),
        ],
        region="hull_a",
        nose_point=(2.30, 0.0, 0.02),
        cap_tail=True,
    )

    # --- blended twin side hulls
    for side in (-1.0, 1.0):
        y = side * 0.52
        b.loft(
            [
                (-2.15, _offset(profile_chine(0.28, 0.17, chine=0.5), dy=y)),
                (-1.35, _offset(profile_chine(0.38, 0.23, chine=0.45), dy=y)),
                (-0.35, _offset(profile_chine(0.32, 0.19, chine=0.42), dy=y)),
            ],
            region="hull_b",
            nose_point=(0.60, y, 0.01),
            cap_tail=True,
        )

    # --- layered decks: broad lower deck, window band, accent ridge on top
    b.loft(
        [
            (-1.70, _offset(profile_chine(0.44, 0.16, chine=0.45), dz=0.30)),
            (-0.90, _offset(profile_chine(0.50, 0.18, chine=0.45), dz=0.32)),
            (0.05, _offset(profile_chine(0.36, 0.13, chine=0.45), dz=0.28)),
        ],
        region="hull_b",
        nose_point=(0.75, 0.0, 0.18),
        tail_point=(-2.05, 0.0, 0.20),
    )
    # window strips along the superstructure flanks (thin vertical slabs)
    win_strip = [(0.00, 0.33), (-1.55, 0.345), (-1.55, 0.41), (0.00, 0.395)]
    b.wing(win_strip, thickness=0.035, z=0.245, region="windows", taper=1.0, plane="xz")
    b.wing(win_strip, thickness=0.035, z=-0.245, region="windows", taper=1.0, plane="xz")
    b.loft(
        [
            (-1.35, _offset(profile_diamond(0.24, 0.10), dz=0.47)),
            (-0.55, _offset(profile_diamond(0.28, 0.12), dz=0.49)),
            (-0.15, _offset(profile_diamond(0.18, 0.09), dz=0.44)),
        ],
        region="accent",
        nose_point=(0.40, 0.0, 0.35),
        tail_point=(-1.70, 0.0, 0.37),
    )

    # --- forward dorsal accent stripe
    b.loft(
        [
            (0.00, _offset(profile_diamond(0.14, 0.09), dz=0.24)),
            (0.70, _offset(profile_diamond(0.17, 0.10), dz=0.22)),
            (1.30, _offset(profile_diamond(0.11, 0.07), dz=0.17)),
        ],
        region="accent",
        nose_point=(1.80, 0.0, 0.10),
        tail_point=(-0.35, 0.0, 0.20),
    )

    # --- forward turret
    b.loft(
        [
            (0.55, _offset(profile_chine(0.18, 0.09, chine=0.5), dz=0.25)),
            (0.85, _offset(profile_chine(0.14, 0.08, chine=0.5), dz=0.24)),
        ],
        region="dark",
        cap_tail=True,
    )
    _gun_barrels(b, 0.85, 0.05, 0.28, length=0.45, radius=0.018)

    # --- swept dart wings with trailing notch
    wing_outline = [
        (0.40, 0.30), (-0.40, 0.48), (-1.60, 0.66), (-1.35, 1.10),
        (-1.85, 1.44), (-1.15, 1.32), (-0.55, 0.88), (0.15, 0.52),
    ]
    b.wing(wing_outline, thickness=0.07, z=-0.05, region="wing", taper=0.82)
    b.wing(wing_outline, thickness=0.07, z=-0.05, region="wing", taper=0.82, flip=True)
    tip_outline = [(-1.20, 1.26), (-1.90, 1.48), (-1.68, 1.58), (-1.06, 1.38)]
    b.wing(tip_outline, thickness=0.08, z=-0.045, region="accent", taper=0.7)
    b.wing(tip_outline, thickness=0.08, z=-0.045, region="accent", taper=0.7, flip=True)

    # --- ventral keel fin
    keel = [(0.15, -0.16), (-0.55, -0.26), (-1.35, -0.62), (-1.65, -0.56), (-1.05, -0.18)]
    b.wing(keel, thickness=0.055, z=0.0, region="wing", taper=0.85, plane="xz")

    # --- greeble skirts on the side-hull flanks
    skirt = [(0.00, 0.06), (-1.60, 0.10), (-1.60, -0.12), (0.00, -0.08)]
    b.wing(skirt, thickness=0.05, z=0.72, region="greeble", taper=1.0, plane="xz")
    b.wing(skirt, thickness=0.05, z=-0.72, region="greeble", taper=1.0, plane="xz")

    # --- cockpit canopy
    b.loft(
        [
            (1.30, _offset(profile_diamond(0.13, 0.05), dz=0.135)),
            (1.60, _offset(profile_diamond(0.10, 0.045), dz=0.12)),
        ],
        region="windows",
        nose_point=(1.85, 0.0, 0.08),
        tail_point=(1.15, 0.0, 0.115),
    )

    # --- engines: pair on each side hull tail + center pair
    _engine_pair(b, -2.13, 0.52, 0.0, scale=1.35)
    _engine_pair(b, -2.23, 0.16, -0.03, scale=1.1)


def build_battleship(b):
    """Massive arrow flagship: split prow, tiered superstructure, 4 engines."""
    # --- main hull
    b.loft(
        [
            (-3.00, profile_chine(0.55, 0.30, chine=0.5)),
            (-2.10, profile_chine(0.85, 0.44, chine=0.45)),
            (-0.80, profile_chine(1.00, 0.50, chine=0.42)),
            (0.40, profile_chine(0.82, 0.42, chine=0.42)),
            (1.30, profile_chine(0.52, 0.26, chine=0.45)),
        ],
        region="hull_a",
        nose_point=(1.85, 0.0, 0.02),
        cap_tail=True,
    )

    # --- split prow: two forward prongs flanking the center wedge
    for side in (-1.0, 1.0):
        b.loft(
            [
                (0.90, _offset(profile_chine(0.34, 0.24, chine=0.5), dy=side * 0.26)),
                (1.90, _offset(profile_chine(0.26, 0.17, chine=0.5), dy=side * 0.31)),
                (2.55, _offset(profile_chine(0.17, 0.11, chine=0.5), dy=side * 0.35)),
            ],
            region="hull_a",
            nose_point=(3.15, side * 0.38, 0.02),
            cap_tail=True,
        )
        # prong accent ridge
        b.loft(
            [
                (1.60, _offset(profile_diamond(0.09, 0.06), dy=side * 0.295, dz=0.10)),
                (2.50, _offset(profile_diamond(0.07, 0.05), dy=side * 0.345, dz=0.08)),
            ],
            region="accent",
            nose_point=(2.95, side * 0.37, 0.06),
            tail_point=(1.20, side * 0.275, 0.09),
        )

    # --- tiered dorsal superstructure
    b.loft(
        [
            (-2.00, _offset(profile_chine(0.62, 0.20, chine=0.45), dz=0.36)),
            (-1.10, _offset(profile_chine(0.68, 0.22, chine=0.45), dz=0.38)),
            (-0.20, _offset(profile_chine(0.50, 0.17, chine=0.45), dz=0.34)),
        ],
        region="hull_b",
        nose_point=(0.55, 0.0, 0.24),
        tail_point=(-2.45, 0.0, 0.26),
    )
    b.loft(
        [
            (-1.65, _offset(profile_chine(0.36, 0.16, chine=0.5), dz=0.54)),
            (-0.85, _offset(profile_chine(0.40, 0.17, chine=0.5), dz=0.55)),
            (-0.30, _offset(profile_chine(0.28, 0.13, chine=0.5), dz=0.50)),
        ],
        region="hull_a",
        nose_point=(0.10, 0.0, 0.40),
        tail_point=(-2.00, 0.0, 0.42),
    )
    # bridge window strips on the tier-2 flanks
    win_strip = [(-0.30, 0.50), (-1.75, 0.515), (-1.75, 0.60), (-0.30, 0.585)]
    b.wing(win_strip, thickness=0.035, z=0.215, region="windows", taper=1.0, plane="xz")
    b.wing(win_strip, thickness=0.035, z=-0.215, region="windows", taper=1.0, plane="xz")
    b.loft(
        [
            (-1.40, _offset(profile_diamond(0.16, 0.10), dz=0.70)),
            (-0.85, _offset(profile_diamond(0.20, 0.12), dz=0.73)),
            (-0.45, _offset(profile_diamond(0.14, 0.09), dz=0.68)),
        ],
        region="accent",
        nose_point=(-0.05, 0.0, 0.58),
        tail_point=(-1.75, 0.0, 0.58),
    )
    # dorsal comms fin
    fin = [(-0.90, 0.70), (-1.50, 0.95), (-1.85, 0.90), (-1.60, 0.62)]
    b.wing(fin, thickness=0.05, z=0.0, region="wing", taper=0.85, plane="xz")

    # --- fore-deck turrets
    b.loft(
        [
            (0.50, _offset(profile_chine(0.24, 0.11, chine=0.5), dz=0.30)),
            (0.85, _offset(profile_chine(0.19, 0.10, chine=0.5), dz=0.29)),
        ],
        region="dark",
        cap_tail=True,
    )
    _gun_barrels(b, 0.85, 0.06, 0.335, length=0.60, radius=0.022)
    b.loft(
        [
            (-0.15, _offset(profile_chine(0.26, 0.12, chine=0.5), dz=0.335)),
            (0.20, _offset(profile_chine(0.21, 0.11, chine=0.5), dz=0.325)),
        ],
        region="dark",
        cap_tail=True,
    )
    _gun_barrels(b, 0.20, 0.065, 0.385, length=0.55, radius=0.022)

    # --- huge swept wings with trailing notch
    wing_outline = [
        (0.60, 0.45), (-0.70, 0.68), (-2.30, 0.92), (-2.00, 1.45),
        (-2.70, 1.90), (-1.90, 1.75), (-1.25, 1.18), (0.20, 0.70),
    ]
    b.wing(wing_outline, thickness=0.085, z=-0.06, region="wing", taper=0.82)
    b.wing(wing_outline, thickness=0.085, z=-0.06, region="wing", taper=0.82, flip=True)
    tip_outline = [(-1.98, 1.66), (-2.76, 1.94), (-2.52, 2.06), (-1.82, 1.82)]
    b.wing(tip_outline, thickness=0.09, z=-0.055, region="accent", taper=0.7)
    b.wing(tip_outline, thickness=0.09, z=-0.055, region="accent", taper=0.7, flip=True)

    # --- ventral keel fins (fore + aft)
    keel_aft = [(-0.90, -0.22), (-1.80, -0.34), (-2.50, -0.78), (-2.85, -0.70), (-2.20, -0.26)]
    b.wing(keel_aft, thickness=0.06, z=0.0, region="wing", taper=0.85, plane="xz")
    keel_fore = [(1.30, -0.10), (0.70, -0.18), (0.30, -0.42), (0.00, -0.40), (0.50, -0.12)]
    b.wing(keel_fore, thickness=0.05, z=0.0, region="wing", taper=0.85, plane="xz")

    # --- greeble flank skirts
    skirt = [(0.45, 0.08), (-2.35, 0.13), (-2.35, -0.15), (0.45, -0.10)]
    b.wing(skirt, thickness=0.06, z=0.50, region="greeble", taper=1.0, plane="xz")
    b.wing(skirt, thickness=0.06, z=-0.50, region="greeble", taper=1.0, plane="xz")

    # --- outboard engine pods + pylons, 4 nozzles total
    for side in (-1.0, 1.0):
        y = side * 0.68
        b.loft(
            [
                (-3.15, _offset(profile_hex(0.22, 0.19), dy=y)),
                (-2.75, _offset(profile_hex(0.32, 0.27), dy=y)),
                (-2.15, _offset(profile_hex(0.26, 0.22), dy=y)),
            ],
            region="hull_b",
            nose_point=(-1.60, y, 0.0),
            cap_tail=True,
        )
    pylon = [(-1.95, 0.35), (-2.90, 0.40), (-2.90, 0.75), (-2.00, 0.72)]
    b.wing(pylon, thickness=0.06, z=0.0, region="hull_b", taper=0.9)
    b.wing(pylon, thickness=0.06, z=0.0, region="hull_b", taper=0.9, flip=True)
    _engine_pair(b, -3.13, 0.68, 0.0, scale=1.5)
    _engine_pair(b, -3.02, 0.24, -0.02, scale=1.6)

    # --- canopy on the fore spine
    b.loft(
        [
            (0.95, _offset(profile_diamond(0.14, 0.05), dz=0.20)),
            (1.20, _offset(profile_diamond(0.10, 0.045), dz=0.185)),
        ],
        region="windows",
        nose_point=(1.45, 0.0, 0.14),
        tail_point=(0.80, 0.0, 0.17),
    )


def build_science(b):
    """Slim survey ship: big lathed sensor dish on a dorsal pylon + booms."""
    # --- slim hull
    b.loft(
        [
            (-1.38, profile_chine(0.24, 0.15, chine=0.5)),
            (-1.05, profile_chine(0.34, 0.21, chine=0.45)),
            (-0.35, profile_chine(0.40, 0.25, chine=0.42)),
            (0.45, profile_chine(0.30, 0.18, chine=0.45)),
        ],
        region="hull_a",
        nose_point=(1.24, 0.0, 0.03),
        cap_tail=True,
    )

    # --- dorsal accent ridge
    b.loft(
        [
            (-0.95, _offset(profile_diamond(0.10, 0.07), dz=0.16)),
            (-0.35, _offset(profile_diamond(0.14, 0.09), dz=0.18)),
            (0.25, _offset(profile_diamond(0.10, 0.07), dz=0.15)),
        ],
        region="accent",
        nose_point=(0.65, 0.0, 0.11),
        tail_point=(-1.15, 0.0, 0.11),
    )

    # --- dish pylon (vertical slab) + big sensor dish facing forward
    pylon = [(0.10, 0.12), (-0.45, 0.12), (-0.60, 0.52), (-0.05, 0.52)]
    b.wing(pylon, thickness=0.07, z=0.0, region="hull_b", taper=0.9, plane="xz")
    dish_c = (0.02, 0.0, 0.60)
    b.lathe(
        [(0.05, 0.46), (-0.06, 0.30), (-0.11, 0.12), (-0.125, 0.02)],
        segments=12, center=dish_c, axis="X", region="accent",
        smooth=True, close=False)
    b.lathe(
        [(0.05, 0.46), (-0.14, 0.28), (-0.26, 0.03)],
        segments=12, center=dish_c, axis="X", region="hull_b",
        smooth=True, close=False)
    # red rim torus around the dish edge
    b.lathe(
        [(-0.02, 0.45), (0.04, 0.485), (0.09, 0.45), (0.04, 0.415), (-0.02, 0.45)],
        segments=12, center=dish_c, axis="X", region="accent",
        smooth=True, close=False)
    # greeble hub on the dish back
    b.lathe(
        [(-0.30, 0.02), (-0.24, 0.10), (-0.14, 0.13)],
        segments=8, center=dish_c, axis="X", region="greeble",
        smooth=False, close=False)
    b.lathe(
        [(0.55, 0.006), (0.02, 0.028)],
        segments=6, center=dish_c, axis="X", region="dark",
        smooth=True, close=False)

    # --- forward instrument booms with glow pods
    for side in (-1.0, 1.0):
        b.loft(
            [
                (0.55, _offset(profile_diamond(0.055, 0.045), dy=side * 0.16, dz=0.02)),
                (1.00, _offset(profile_diamond(0.04, 0.032), dy=side * 0.24, dz=0.03)),
            ],
            region="metal",
            nose_point=(1.38, side * 0.30, 0.04),
            tail_point=(0.40, side * 0.13, 0.02),
        )
        b.lathe(
            [(0.06, 0.012), (-0.02, 0.026), (-0.10, 0.008)],
            segments=6, center=(1.10, side * 0.262, 0.033), axis="X",
            region="glow", smooth=False, close=True)

    # --- small swept wings
    wing_outline = [
        (0.05, 0.13), (-0.40, 0.24), (-0.95, 0.33), (-0.80, 0.58),
        (-1.10, 0.76), (-0.70, 0.70), (-0.35, 0.45), (-0.05, 0.26),
    ]
    b.wing(wing_outline, thickness=0.05, z=-0.02, region="wing", taper=0.8)
    b.wing(wing_outline, thickness=0.05, z=-0.02, region="wing", taper=0.8, flip=True)
    tip_outline = [(-0.74, 0.66), (-1.14, 0.80), (-0.98, 0.86), (-0.62, 0.72)]
    b.wing(tip_outline, thickness=0.06, z=-0.015, region="accent", taper=0.7)
    b.wing(tip_outline, thickness=0.06, z=-0.015, region="accent", taper=0.7, flip=True)

    # --- keel fin + greeble skirts
    keel = [(0.00, -0.09), (-0.40, -0.14), (-0.85, -0.36), (-1.05, -0.33), (-0.70, -0.10)]
    b.wing(keel, thickness=0.04, z=0.0, region="wing", taper=0.85, plane="xz")
    skirt = [(0.00, 0.05), (-0.85, 0.08), (-0.85, -0.08), (0.00, -0.06)]
    b.wing(skirt, thickness=0.045, z=0.195, region="greeble", taper=1.0, plane="xz")
    b.wing(skirt, thickness=0.045, z=-0.195, region="greeble", taper=1.0, plane="xz")

    # --- canopy
    b.loft(
        [
            (0.45, _offset(profile_diamond(0.11, 0.045), dz=0.10)),
            (0.68, _offset(profile_diamond(0.085, 0.04), dz=0.09)),
        ],
        region="windows",
        nose_point=(0.92, 0.0, 0.055),
        tail_point=(0.32, 0.0, 0.085),
    )

    # --- engines
    _engine_pair(b, -1.36, 0.115, 0.0, scale=0.95)


def build_builder(b):
    """Compact tug: faceted cargo pods on the flanks + forward crane boom."""
    # --- stubby hull
    b.loft(
        [
            (-1.15, profile_chine(0.32, 0.21, chine=0.5)),
            (-0.70, profile_chine(0.46, 0.29, chine=0.45)),
            (-0.05, profile_chine(0.50, 0.31, chine=0.42)),
            (0.50, profile_chine(0.36, 0.23, chine=0.45)),
        ],
        region="hull_a",
        nose_point=(0.92, 0.0, 0.03),
        cap_tail=True,
    )

    # --- dorsal accent ridge
    b.loft(
        [
            (-0.85, _offset(profile_diamond(0.11, 0.07), dz=0.19)),
            (-0.30, _offset(profile_diamond(0.15, 0.10), dz=0.21)),
            (0.15, _offset(profile_diamond(0.11, 0.07), dz=0.18)),
        ],
        region="accent",
        nose_point=(0.50, 0.0, 0.13),
        tail_point=(-1.05, 0.0, 0.13),
    )

    # --- faceted flank cargo pods with accent straps
    for side in (-1.0, 1.0):
        y = side * 0.46
        b.loft(
            [
                (-0.95, _offset(profile_hex(0.20, 0.18), dy=y)),
                (-0.55, _offset(profile_hex(0.30, 0.27), dy=y)),
                (0.05, _offset(profile_hex(0.30, 0.27), dy=y)),
                (0.40, _offset(profile_hex(0.20, 0.18), dy=y)),
            ],
            region="hull_b",
            nose_point=(0.68, y, 0.0),
            tail_point=(-1.18, y, 0.0),
        )
        b.loft(
            [
                (-0.60, _offset(profile_diamond(0.10, 0.06), dy=y, dz=0.15)),
                (0.10, _offset(profile_diamond(0.10, 0.06), dy=y, dz=0.15)),
            ],
            region="accent",
            nose_point=(0.30, y, 0.10),
            tail_point=(-0.80, y, 0.10),
        )

    # --- forward crane boom with hex joint and hook blade
    b.loft(
        [
            (0.55, _offset(profile_diamond(0.10, 0.09), dz=0.10)),
            (0.95, _offset(profile_diamond(0.07, 0.065), dz=0.17)),
        ],
        region="metal",
        nose_point=(1.28, 0.0, 0.25),
        tail_point=(0.42, 0.0, 0.07),
    )
    b.lathe(
        [(-0.08, 0.06), (0.08, 0.06)],
        segments=6, center=(0.95, 0.0, 0.17), axis="Y",
        region="dark", smooth=False, close=True)
    hook = [(1.02, 0.24), (1.32, 0.30), (1.29, 0.00), (1.15, 0.05)]
    b.wing(hook, thickness=0.06, z=0.0, region="accent", taper=0.85, plane="xz")

    # --- keel fin + ventral greeble plate
    keel = [(0.05, -0.12), (-0.35, -0.18), (-0.75, -0.40), (-0.95, -0.36), (-0.60, -0.13)]
    b.wing(keel, thickness=0.05, z=0.0, region="wing", taper=0.85, plane="xz")
    belly = [(0.30, 0.16), (-0.90, 0.20), (-0.90, -0.20), (0.30, -0.16)]
    b.wing(belly, thickness=0.05, z=-0.19, region="greeble", taper=1.0)

    # --- cabin canopy
    b.loft(
        [
            (0.45, _offset(profile_diamond(0.16, 0.06), dz=0.13)),
            (0.68, _offset(profile_diamond(0.12, 0.05), dz=0.115)),
        ],
        region="windows",
        nose_point=(0.90, 0.0, 0.07),
        tail_point=(0.30, 0.0, 0.11),
    )

    # --- engines
    _engine_pair(b, -1.10, 0.17, -0.01, scale=1.15)


def build_station(b):
    """Vertical faceted spindle, octagonal habitat ring, 4 pad arms."""
    # --- central spindle (octagonal lathe, faceted)
    b.lathe(
        [
            (-1.45, 0.04), (-1.15, 0.20), (-0.75, 0.30), (-0.40, 0.42),
            (0.00, 0.45), (0.40, 0.42), (0.75, 0.32), (1.15, 0.18), (1.50, 0.03),
        ],
        segments=8, center=(0, 0, 0), axis="Z", region="hull_a",
        smooth=False, close=True)

    # --- main octagonal habitat ring
    _oct_ring(b, 0.15, 1.32, 0.10, 0.13, "hull_b")
    # --- lower accent collar ring + upper accent collar on the cone
    _oct_ring(b, -0.70, 0.40, 0.07, 0.10, "accent")
    _oct_ring(b, 0.95, 0.24, 0.05, 0.08, "accent")

    # --- 4 radial arms ending in landing pads
    arm = [(0.32, 0.12), (1.20, 0.09), (1.42, 0.14), (1.42, -0.14), (1.20, -0.09), (0.32, -0.12)]
    for ang in (0.0, 90.0, 180.0, 270.0):
        b.wing(_rot_xy(arm, ang), thickness=0.11, z=0.15, region="wing", taper=0.85)
        px = 1.55 * math.cos(math.radians(ang))
        py = 1.55 * math.sin(math.radians(ang))
        b.lathe(
            [(-0.14, 0.04), (-0.07, 0.23), (0.07, 0.23), (0.13, 0.04)],
            segments=8, center=(px, py, 0.15), axis="Z", region="hull_b",
            smooth=False, close=True)
        b.lathe(
            [(0.13, 0.10), (0.17, 0.02)],
            segments=8, center=(px, py, 0.15), axis="Z", region="glow",
            smooth=False, close=False)

    # --- window bands on the spindle
    b.lathe([(0.42, 0.435), (0.60, 0.40)], segments=8, center=(0, 0, 0),
            axis="Z", region="windows", smooth=False, close=False)
    b.lathe([(-0.55, 0.38), (-0.40, 0.435)], segments=8, center=(0, 0, 0),
            axis="Z", region="windows", smooth=False, close=False)

    # --- greeble machinery collar
    b.lathe([(0.80, 0.315), (0.98, 0.27)], segments=8, center=(0, 0, 0),
            axis="Z", region="greeble", smooth=False, close=False)

    # --- top mast + glowing tip
    b.lathe([(1.45, 0.05), (1.80, 0.012)], segments=6, center=(0, 0, 0),
            axis="Z", region="metal", smooth=True, close=False)
    b.lathe([(1.80, 0.012), (1.90, 0.002)], segments=6, center=(0, 0, 0),
            axis="Z", region="glow", smooth=True, close=False)

    # --- station-keeping thruster at the base
    b.lathe([(-1.30, 0.16), (-1.52, 0.11), (-1.58, 0.04)], segments=8,
            center=(0, 0, 0), axis="Z", region="dark", smooth=False, close=False)
    b.lathe([(-1.54, 0.10), (-1.66, 0.01)], segments=8, center=(0, 0, 0),
            axis="Z", region="engine", smooth=False, close=False)


def build_stellar_station(b):
    """Grand double-ring station: 6 pad arms, glowing octahedral core."""
    # --- tall spindle with an hourglass waist for the glowing core
    b.lathe(
        [
            (-2.00, 0.04), (-1.60, 0.22), (-1.15, 0.36), (-0.70, 0.48),
            (-0.30, 0.34), (0.30, 0.34), (0.70, 0.50), (1.20, 0.42),
            (1.70, 0.22), (2.10, 0.04),
        ],
        segments=8, center=(0, 0, 0), axis="Z", region="hull_a",
        smooth=False, close=True)

    # --- glowing octahedral core at the waist
    b.lathe(
        [(-0.50, 0.18), (-0.12, 0.62), (0.12, 0.62), (0.50, 0.18)],
        segments=8, center=(0, 0, 0), axis="Z", region="glow",
        smooth=False, close=False)

    # --- double habitat rings
    _oct_ring(b, 0.70, 1.68, 0.12, 0.16, "hull_b")
    _oct_ring(b, -0.60, 1.28, 0.10, 0.14, "hull_b")

    # --- 6 radial arms with landing pads (upper ring plane)
    arm = [(0.35, 0.13), (1.60, 0.10), (2.10, 0.16), (2.10, -0.16), (1.60, -0.10), (0.35, -0.13)]
    for i in range(6):
        ang = i * 60.0
        b.wing(_rot_xy(arm, ang), thickness=0.12, z=0.70, region="wing", taper=0.85)
        px = 2.32 * math.cos(math.radians(ang))
        py = 2.32 * math.sin(math.radians(ang))
        b.lathe(
            [(-0.16, 0.05), (-0.08, 0.27), (0.08, 0.27), (0.15, 0.05)],
            segments=8, center=(px, py, 0.70), axis="Z", region="hull_b",
            smooth=False, close=True)
        b.lathe(
            [(0.15, 0.12), (0.20, 0.02)],
            segments=8, center=(px, py, 0.70), axis="Z", region="glow",
            smooth=False, close=False)

    # --- 3 lower spokes into the small ring
    spoke = [(0.30, 0.10), (1.30, 0.07), (1.30, -0.07), (0.30, -0.10)]
    for ang in (30.0, 150.0, 270.0):
        b.wing(_rot_xy(spoke, ang), thickness=0.10, z=-0.60, region="wing", taper=0.9)

    # --- window bands
    b.lathe([(0.90, 0.50), (1.10, 0.46)], segments=8, center=(0, 0, 0),
            axis="Z", region="windows", smooth=False, close=False)
    b.lathe([(-1.00, 0.42), (-0.82, 0.46)], segments=8, center=(0, 0, 0),
            axis="Z", region="windows", smooth=False, close=False)

    # --- upper accent collar
    _oct_ring(b, 1.45, 0.39, 0.06, 0.09, "accent")

    # --- greeble machinery collar
    b.lathe([(-1.45, 0.30), (-1.25, 0.345)], segments=8, center=(0, 0, 0),
            axis="Z", region="greeble", smooth=False, close=False)

    # --- top mast + glowing tip
    b.lathe([(2.10, 0.06), (2.55, 0.012)], segments=6, center=(0, 0, 0),
            axis="Z", region="metal", smooth=True, close=False)
    b.lathe([(2.55, 0.012), (2.65, 0.002)], segments=6, center=(0, 0, 0),
            axis="Z", region="glow", smooth=True, close=False)

    # --- station-keeping thruster at the base
    b.lathe([(-1.85, 0.18), (-2.05, 0.12), (-2.10, 0.05)], segments=8,
            center=(0, 0, 0), axis="Z", region="dark", smooth=False, close=False)
    b.lathe([(-2.06, 0.11), (-2.20, 0.01)], segments=8, center=(0, 0, 0),
            axis="Z", region="engine", smooth=False, close=False)


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
