"""Tidal ship set — aquatic organic civilization. Smooth teardrop / manta / ray
silhouettes following assets/icons/fleet/fleet_scout_*.svg (teal concentric
arcs, #3fd2c7). Deep blue-teal skin with bioluminescent glow veins; engines are
glowing gill vents, not open nozzles.

Ships face +X, up is +Z, symmetric across Y. Everything lofts from smooth lens
profiles (smooth=True) so the hulls read as living, wet-skinned creatures.
"""

import math

from shipgen_lib import (
    Palette,
    profile_diamond,
    profile_lens,
)

PALETTE = Palette(
    hull=(0.24, 0.42, 0.48),
    hull_b=(0.15, 0.26, 0.32),
    dark=(0.07, 0.13, 0.17),
    accent=(0.25, 0.82, 0.78),          # scout icon teal #3fd2c7
    metal=(0.40, 0.52, 0.55),
    engine_glow=(0.40, 1.00, 0.95),
    window_glow=(1.00, 0.94, 0.80),
    accent_glow=(0.32, 0.95, 0.88),
    roughness_hull=0.40,                 # wet sheen
    roughness_metal=0.30,
    panel_contrast=0.06,                 # smooth skin, few panels
    grime=0.03,
)

PREVIEW_ACCENT = (0.45, 0.95, 0.95)


def _offset(profile, dy=0.0, dz=0.0):
    return [(y + dy, z + dz) for (y, z) in profile]


def _manta_wing(root_x, tip_x, span, root_chord, tip_back, curl=0.0):
    """Smooth swept manta/ray wing outline (top view, +Y side).

    Traces the leading edge out to the tip then the trailing edge back, with
    a gentle S-curve so the fin looks grown rather than cut. curl bends the
    tip backward for a fluke look."""
    lead, trail = [], []
    steps = 7
    for i in range(steps + 1):
        t = i / steps
        # leading edge sweeps back as it goes outboard
        y = span * t
        x_lead = root_x - (root_x - tip_x) * (t ** 1.35)
        x_trail = (root_x - root_chord) - (root_x - root_chord - (tip_x - tip_back)) * (t ** 0.7)
        x_trail -= curl * (t ** 2)
        lead.append((x_lead, y))
        trail.append((x_trail, y))
    return lead + list(reversed(trail))


def _gill_row(b, x, span, count, z_base, scale=1.0):
    """Row of recessed organic glow pods at the tail (bioluminescent vents).

    Each pod is a short lathed cup with a glowing inner disc, so it reads as a
    living vent rather than a flat card. Pods shrink toward the row edges."""
    for i in range(count):
        t = (i + 0.5) / count - 0.5
        y = t * span
        pod = scale * (1.0 - 0.35 * abs(t) * 2.0)
        center = (x, y, z_base)
        # outer cowl (dark ring, slightly flared)
        b.lathe(
            [(0.11 * pod, 0.045 * pod), (0.01 * pod, 0.085 * pod), (-0.09 * pod, 0.070 * pod)],
            segments=8, center=center, axis="X", region="hull_b", smooth=True)
        # recessed glow disc
        b.lathe(
            [(-0.04 * pod, 0.060 * pod), (-0.11 * pod, 0.004)],
            segments=8, center=center, axis="X", region="engine",
            smooth=True, close=False)


def _caudal(b, x_root, reach, span, region="wing", z=0.0, thickness=0.05):
    """Horizontal two-lobe tail fluke (whale/manta caudal fin), plane xy.

    Sits flat with the body so it reads as a swimming tail, not a vertical
    pale sail. Built as one lobe mirrored to both sides."""
    lobe = [
        (x_root, 0.02), (x_root - reach * 0.45, span * 0.55),
        (x_root - reach, span), (x_root - reach * 1.12, span * 0.9),
        (x_root - reach * 0.6, span * 0.4), (x_root - reach * 0.35, 0.015),
    ]
    b.wing(lobe, thickness=thickness, z=z, region=region, taper=0.78)
    b.wing(lobe, thickness=thickness, z=z, region=region, taper=0.78, flip=True)
    # bioluminescent trailing edge
    edge = [
        (x_root - reach * 0.75, span * 0.55), (x_root - reach, span),
        (x_root - reach * 1.12, span * 0.9), (x_root - reach * 0.85, span * 0.5),
    ]
    b.wing(edge, thickness=thickness * 1.1, z=z, region="glow", taper=0.7)
    b.wing(edge, thickness=thickness * 1.1, z=z, region="glow", taper=0.7, flip=True)


def _dorsal_vein(b, x0, x1, z, width, height, region="glow"):
    """Bioluminescent vein ridge running along the spine."""
    b.loft(
        [
            (x0, _offset(profile_diamond(width, height), dz=z)),
            ((x0 + x1) * 0.5, _offset(profile_diamond(width * 1.25, height * 1.1), dz=z + height * 0.2)),
            (x1, _offset(profile_diamond(width, height), dz=z)),
        ],
        region=region,
        nose_point=(x1 + (x1 - x0) * 0.25, 0.0, z),
        tail_point=(x0 - (x1 - x0) * 0.25, 0.0, z),
        smooth=True,
    )


def build_corvette(b):
    # --- smooth ray body: lens sections, wide and flat
    b.loft(
        [
            (-1.15, profile_lens(0.30, 0.16)),
            (-0.75, profile_lens(0.66, 0.26)),
            (-0.15, profile_lens(0.90, 0.32)),
            (0.55, profile_lens(0.62, 0.24)),
            (1.00, profile_lens(0.26, 0.13)),
        ],
        region="hull_a",
        nose_point=(1.45, 0.0, 0.0),
        tail_point=(-1.30, 0.0, 0.0),
        smooth=True,
    )

    # --- curved manta wing fins
    wing = _manta_wing(0.35, -0.75, 1.15, 0.75, 0.30, curl=0.25)
    b.wing(wing, thickness=0.05, z=-0.03, region="wing", taper=0.88)
    b.wing(wing, thickness=0.05, z=-0.03, region="wing", taper=0.88, flip=True)

    # --- accent vein along the wing leading edges
    vein = _manta_wing(0.32, -0.55, 1.05, 0.14, 0.05, curl=0.22)
    b.wing(vein, thickness=0.055, z=0.02, region="glow", taper=0.8)
    b.wing(vein, thickness=0.055, z=0.02, region="glow", taper=0.8, flip=True)

    # --- glow veins fanning across the wings (break up the flat surface)
    for k in range(2):
        r = 0.4 + k * 0.32
        arc = _manta_wing(0.28 - k * 0.12, -0.55 - k * 0.14, 0.42 + r, 0.07, 0.02, curl=0.2)
        b.wing(arc, thickness=0.05, z=0.005, region="glow", taper=0.8)
        b.wing(arc, thickness=0.05, z=0.005, region="glow", taper=0.8, flip=True)

    # --- dorsal bioluminescent vein
    _dorsal_vein(b, -0.85, 0.55, 0.17, 0.07, 0.05)

    # --- horizontal caudal tail fluke
    _caudal(b, -1.15, 0.42, 0.5, z=0.0)

    # --- eye windows near the nose
    b.loft(
        [
            (0.62, _offset(profile_lens(0.20, 0.08), dz=0.10)),
            (0.85, _offset(profile_lens(0.13, 0.06), dz=0.09)),
        ],
        region="windows",
        nose_point=(1.05, 0.0, 0.05),
        tail_point=(0.45, 0.0, 0.09),
        smooth=True,
    )

    # --- gill engines
    _gill_row(b, -1.18, 0.34, 3, 0.02, scale=1.0)


def build_destroyer(b):
    """Elongated eel/barracuda with a tall dorsal fin and trailing fluke."""
    b.loft(
        [
            (-1.85, profile_lens(0.24, 0.18)),
            (-1.30, profile_lens(0.44, 0.34)),
            (-0.55, profile_lens(0.56, 0.42)),
            (0.35, profile_lens(0.44, 0.32)),
            (1.15, profile_lens(0.26, 0.19)),
        ],
        region="hull_a",
        nose_point=(1.95, 0.0, 0.0),
        tail_point=(-2.05, 0.0, 0.0),
        smooth=True,
    )

    # --- tall dorsal fin (shark-like)
    dorsal = [(0.15, 0.30), (-0.20, 0.44), (-0.55, 0.78), (-0.85, 0.72), (-0.60, 0.40), (-0.35, 0.30)]
    b.wing(dorsal, thickness=0.055, z=0.0, region="wing", taper=0.8, plane="xz")
    # fin accent edge
    dorsal_edge = [(-0.30, 0.50), (-0.55, 0.76), (-0.80, 0.72), (-0.62, 0.50)]
    b.wing(dorsal_edge, thickness=0.06, z=0.0, region="glow", taper=0.75, plane="xz")

    # --- pectoral fins
    wing = _manta_wing(-0.10, -1.05, 0.95, 0.60, 0.24, curl=0.30)
    b.wing(wing, thickness=0.045, z=-0.05, region="wing", taper=0.86)
    b.wing(wing, thickness=0.045, z=-0.05, region="wing", taper=0.86, flip=True)

    # --- dorsal + flank veins
    _dorsal_vein(b, -1.45, 0.95, 0.24, 0.06, 0.045)
    flank = _manta_wing(-0.20, -0.95, 0.42, 0.10, 0.04, curl=0.1)
    b.wing(flank, thickness=0.05, z=0.14, region="glow", taper=0.85)
    b.wing(flank, thickness=0.05, z=0.14, region="glow", taper=0.85, flip=True)

    # --- glow veins fanning across the pectoral fins
    for k in range(3):
        r = 0.3 + k * 0.24
        arc = _manta_wing(-0.05 - k * 0.08, -0.75 - k * 0.12, 0.4 + r, 0.06, 0.02, curl=0.22)
        b.wing(arc, thickness=0.045, z=-0.03, region="glow", taper=0.8)
        b.wing(arc, thickness=0.045, z=-0.03, region="glow", taper=0.8, flip=True)

    # --- horizontal caudal tail fluke (forked)
    _caudal(b, -1.85, 0.48, 0.62, z=0.0)

    # --- eye windows
    b.loft(
        [
            (0.70, _offset(profile_lens(0.20, 0.11), dz=0.12)),
            (1.00, _offset(profile_lens(0.13, 0.08), dz=0.10)),
        ],
        region="windows",
        nose_point=(1.35, 0.0, 0.06),
        tail_point=(0.50, 0.0, 0.11),
        smooth=True,
    )

    _gill_row(b, -1.85, 0.30, 4, 0.02, scale=1.05)


def build_cruiser(b):
    """Broad manta: wide curved wings blended into a flat teardrop body."""
    b.loft(
        [
            (-1.95, profile_lens(0.44, 0.22)),
            (-1.25, profile_lens(0.90, 0.34)),
            (-0.30, profile_lens(1.20, 0.42)),
            (0.70, profile_lens(0.80, 0.30)),
            (1.35, profile_lens(0.34, 0.16)),
        ],
        region="hull_a",
        nose_point=(2.05, 0.0, 0.0),
        tail_point=(-2.20, 0.0, 0.0),
        smooth=True,
    )

    # --- broad manta wings
    wing = _manta_wing(0.75, -1.35, 1.85, 1.35, 0.55, curl=0.45)
    b.wing(wing, thickness=0.06, z=-0.04, region="wing", taper=0.9)
    b.wing(wing, thickness=0.06, z=-0.04, region="wing", taper=0.9, flip=True)

    # --- wing glow veins fanning out (echoing scout arcs)
    for k in range(3):
        r = 0.55 + k * 0.35
        arc = _manta_wing(0.55 - k * 0.15, -0.95 - k * 0.15, 0.55 + r, 0.10, 0.03, curl=0.35)
        b.wing(arc, thickness=0.05, z=0.06, region="glow", taper=0.82)
        b.wing(arc, thickness=0.05, z=0.06, region="glow", taper=0.82, flip=True)

    # --- raised central ridge with window band
    b.loft(
        [
            (-1.10, _offset(profile_lens(0.44, 0.16), dz=0.30)),
            (-0.30, _offset(profile_lens(0.52, 0.19), dz=0.34)),
            (0.55, _offset(profile_lens(0.36, 0.14), dz=0.28)),
        ],
        region="hull_b",
        nose_point=(1.15, 0.0, 0.16),
        tail_point=(-1.65, 0.0, 0.18),
        smooth=True,
    )
    b.loft(
        [
            (-0.55, _offset(profile_lens(0.30, 0.09), dz=0.44)),
            (0.05, _offset(profile_lens(0.34, 0.10), dz=0.45)),
            (0.55, _offset(profile_lens(0.22, 0.07), dz=0.40)),
        ],
        region="windows",
        nose_point=(0.95, 0.0, 0.34),
        tail_point=(-0.95, 0.0, 0.36),
        smooth=True,
    )
    _dorsal_vein(b, -1.55, 1.05, 0.50, 0.07, 0.05)

    # --- horizontal caudal tail fluke
    _caudal(b, -2.05, 0.55, 0.7, z=0.0, thickness=0.06)

    _gill_row(b, -2.05, 0.42, 4, 0.0, scale=1.2)


def build_battleship(b):
    """Deep leviathan: layered shell segments, stacked pectoral fins, big flukes."""
    b.loft(
        [
            (-2.80, profile_lens(0.44, 0.30)),
            (-1.90, profile_lens(0.92, 0.56)),
            (-0.70, profile_lens(1.18, 0.68)),
            (0.55, profile_lens(0.92, 0.52)),
            (1.55, profile_lens(0.42, 0.26)),
        ],
        region="hull_a",
        nose_point=(2.70, 0.0, 0.0),
        tail_point=(-3.05, 0.0, 0.0),
        smooth=True,
    )

    # --- layered overlapping shell plates along the back (scale segments)
    shell_x = [-1.7, -0.9, -0.1, 0.7]
    for i, sx in enumerate(shell_x):
        w = 1.05 - i * 0.14
        b.loft(
            [
                (sx - 0.42, _offset(profile_lens(w * 0.82, 0.20), dz=0.30 + i * 0.015)),
                (sx, _offset(profile_lens(w, 0.26), dz=0.36 + i * 0.02)),
                (sx + 0.42, _offset(profile_lens(w * 0.7, 0.16), dz=0.28 + i * 0.015)),
            ],
            region="hull_b",
            nose_point=(sx + 0.62, 0.0, 0.22 + i * 0.02),
            tail_point=(sx - 0.60, 0.0, 0.24 + i * 0.015),
            smooth=True,
        )

    # --- stacked pectoral fins (upper + lower)
    wing_up = _manta_wing(0.55, -1.75, 2.05, 1.55, 0.65, curl=0.55)
    b.wing(wing_up, thickness=0.07, z=0.10, region="wing", taper=0.9)
    b.wing(wing_up, thickness=0.07, z=0.10, region="wing", taper=0.9, flip=True)
    wing_lo = _manta_wing(0.05, -1.95, 1.55, 1.10, 0.50, curl=0.45)
    b.wing(wing_lo, thickness=0.06, z=-0.22, region="wing", taper=0.88)
    b.wing(wing_lo, thickness=0.06, z=-0.22, region="wing", taper=0.88, flip=True)

    # --- glow veins fanning across the upper wings
    for k in range(4):
        r = 0.6 + k * 0.4
        arc = _manta_wing(0.4 - k * 0.12, -1.2 - k * 0.18, 0.7 + r, 0.11, 0.03, curl=0.4)
        b.wing(arc, thickness=0.05, z=0.16, region="glow", taper=0.82)
        b.wing(arc, thickness=0.05, z=0.16, region="glow", taper=0.82, flip=True)
    _dorsal_vein(b, -2.2, 1.2, 0.62, 0.09, 0.06)

    # --- crown window ridge (bridge)
    b.loft(
        [
            (-0.55, _offset(profile_lens(0.34, 0.11), dz=0.60)),
            (0.15, _offset(profile_lens(0.40, 0.12), dz=0.62)),
            (0.65, _offset(profile_lens(0.26, 0.08), dz=0.55)),
        ],
        region="windows",
        nose_point=(1.05, 0.0, 0.46),
        tail_point=(-1.05, 0.0, 0.50),
        smooth=True,
    )

    # --- big horizontal whale-tail flukes
    _caudal(b, -2.85, 0.72, 1.05, z=0.05, thickness=0.08)

    _gill_row(b, -2.95, 0.52, 5, 0.0, scale=1.5)


def build_science(b):
    """Survey ray with concentric sensor arc fins — the scout icon in 3D."""
    b.loft(
        [
            (-1.15, profile_lens(0.26, 0.15)),
            (-0.70, profile_lens(0.52, 0.24)),
            (-0.10, profile_lens(0.70, 0.30)),
            (0.55, profile_lens(0.48, 0.22)),
            (0.95, profile_lens(0.22, 0.12)),
        ],
        region="hull_a",
        nose_point=(1.35, 0.0, 0.0),
        tail_point=(-1.30, 0.0, 0.0),
        smooth=True,
    )

    # --- three concentric sensor arcs on a dorsal mount (fleet_scout icon)
    mount = [(0.05, 0.10), (-0.35, 0.10), (-0.45, 0.34), (-0.05, 0.34)]
    b.wing(mount, thickness=0.08, z=0.0, region="hull_b", taper=0.9, plane="xz")
    center = (-0.05, 0.0, 0.42)
    for k in range(3):
        radius = 0.24 + k * 0.20
        # partial ring arc (lathe a thin torus, front-facing quarter emphasis)
        b.lathe(
            [(0.03, radius + 0.03), (0.0, radius + 0.055), (-0.03, radius + 0.03),
             (0.0, radius + 0.005)],
            segments=20, center=center, axis="X", region="accent",
            smooth=True, close=False)
    # sensor bead at the focus
    b.lathe(
        [(0.08, 0.0), (0.05, 0.06), (0.0, 0.08), (-0.05, 0.05)],
        segments=10, center=center, axis="X", region="glow", smooth=True, close=True)

    # --- forward feeler booms
    for side in (-1.0, 1.0):
        boom = [(1.05, side * 0.10), (1.55, side * 0.16), (1.58, side * 0.20), (1.05, side * 0.15)]
        b.wing(boom, thickness=0.04, z=0.02, region="metal", taper=1.0)
        b.lathe([(0.0, 0.03), (0.08, 0.0)], segments=8,
                center=(1.55, side * 0.18, 0.02), axis="X", region="glow", smooth=True)

    # --- pectoral fins
    wing = _manta_wing(0.10, -0.90, 0.95, 0.55, 0.22, curl=0.25)
    b.wing(wing, thickness=0.045, z=-0.03, region="wing", taper=0.88)
    b.wing(wing, thickness=0.045, z=-0.03, region="wing", taper=0.88, flip=True)
    _dorsal_vein(b, -0.95, 0.65, 0.16, 0.05, 0.035)

    _gill_row(b, -1.15, 0.28, 3, 0.0, scale=0.9)


def build_builder(b):
    """Rounded nautilus tug: coiled shell body, forward extractor mandibles."""
    b.loft(
        [
            (-1.05, profile_lens(0.40, 0.34)),
            (-0.60, profile_lens(0.66, 0.56)),
            (-0.05, profile_lens(0.72, 0.62)),
            (0.45, profile_lens(0.52, 0.46)),
            (0.80, profile_lens(0.28, 0.24)),
        ],
        region="hull_a",
        nose_point=(1.05, 0.0, 0.0),
        tail_point=(-1.20, 0.0, 0.0),
        smooth=True,
    )

    # --- spiral shell ridges (stacked lens rings wrapping the back)
    for k in range(4):
        sx = -0.65 + k * 0.4
        rad = 0.60 - k * 0.09
        b.lathe(
            [(0.06, rad * 0.5), (0.0, rad), (-0.06, rad * 0.5)],
            segments=14, center=(sx, 0.0, -0.02), axis="X",
            region="hull_b" if k % 2 else "accent", smooth=True, close=False)

    # --- forward extractor mandibles (curved prongs)
    for side in (-1.0, 1.0):
        mand = [(0.85, side * 0.18), (1.35, side * 0.30), (1.55, side * 0.22),
                (1.30, side * 0.12), (0.90, side * 0.10)]
        b.wing(mand, thickness=0.10, z=0.0, region="hull_b", taper=0.85)
        b.lathe([(0.0, 0.05), (0.14, 0.0)], segments=8,
                center=(1.5, side * 0.24, 0.0), axis="X", region="glow", smooth=True)

    # --- side cargo shell pods
    for side in (-1.0, 1.0):
        b.loft(
            [
                (-0.75, _offset(profile_lens(0.26, 0.26), dy=side * 0.58)),
                (-0.35, _offset(profile_lens(0.34, 0.34), dy=side * 0.62)),
                (0.05, _offset(profile_lens(0.24, 0.24), dy=side * 0.58)),
            ],
            region="hull_b",
            nose_point=(0.35, side * 0.55, 0.0),
            tail_point=(-1.05, side * 0.55, 0.0),
            smooth=True,
        )
    _dorsal_vein(b, -0.85, 0.55, 0.30, 0.06, 0.05)

    _gill_row(b, -1.10, 0.32, 3, 0.0, scale=1.1)


def build_station(b):
    """Nautilus reef station: stacked shell domes + radial fin blades."""
    # --- central stacked-dome spire (nautilus shell), axis Z
    dome_levels = [
        (-0.20, 1.05), (0.35, 0.92), (0.85, 0.74), (1.30, 0.54), (1.70, 0.32),
    ]
    for i in range(len(dome_levels) - 1):
        z0, r0 = dome_levels[i]
        z1, r1 = dome_levels[i + 1]
        b.lathe(
            [(0.0, r0), (z1 - z0, r1)],
            segments=14, center=(0.0, 0.0, z0), axis="Z",
            region="hull_a" if i % 2 == 0 else "hull_b", smooth=True, close=False)
    # crown dome
    b.lathe(
        [(0.0, 0.32), (0.14, 0.22), (0.24, 0.0)],
        segments=14, center=(0.0, 0.0, 1.70), axis="Z", region="accent",
        smooth=True, close=False)
    # base foot
    b.lathe(
        [(0.0, 0.85), (-0.20, 1.05), (-0.30, 0.80)],
        segments=14, center=(0.0, 0.0, -0.20), axis="Z", region="hull_b",
        smooth=True, close=False)

    # --- glowing habitat ring band
    b.lathe(
        [(-0.10, 1.02), (0.0, 1.12), (0.10, 1.02), (0.0, 0.98)],
        segments=20, center=(0.0, 0.0, 0.30), axis="Z", region="glow",
        smooth=True, close=False)

    # --- radial fin blades (curved coral fronds) around the base
    arms = 5
    for i in range(arms):
        ang = i * math.tau / arms
        c, s = math.cos(ang), math.sin(ang)
        # blade outline in XY, rotated into place
        blade = [(0.85, 0.0), (1.75, 0.10), (2.05, 0.02), (1.75, -0.10), (0.85, -0.05)]
        rot = [(x * c - y * s, x * s + y * c) for (x, y) in blade]
        b.wing(rot, thickness=0.08, z=0.10, region="wing", taper=0.85)
        # glow tip
        tip = [(1.75, 0.0), (2.05, 0.06), (2.15, 0.0), (2.05, -0.06)]
        rott = [(x * c - y * s, x * s + y * c) for (x, y) in tip]
        b.wing(rott, thickness=0.09, z=0.10, region="glow", taper=0.8)


def build_stellar_station(b):
    """Grand reef citadel: taller shell spire, twin fin tiers, glow-vein core."""
    dome_levels = [
        (-0.30, 1.55), (0.35, 1.40), (1.00, 1.18), (1.60, 0.92),
        (2.15, 0.62), (2.60, 0.34),
    ]
    for i in range(len(dome_levels) - 1):
        z0, r0 = dome_levels[i]
        z1, r1 = dome_levels[i + 1]
        b.lathe(
            [(0.0, r0), (z1 - z0, r1)],
            segments=16, center=(0.0, 0.0, z0), axis="Z",
            region="hull_a" if i % 2 == 0 else "hull_b", smooth=True, close=False)
    b.lathe(
        [(0.0, 0.34), (0.18, 0.24), (0.32, 0.0)],
        segments=16, center=(0.0, 0.0, 2.60), axis="Z", region="accent",
        smooth=True, close=False)
    b.lathe(
        [(0.0, 1.30), (-0.28, 1.55), (-0.40, 1.20)],
        segments=16, center=(0.0, 0.0, -0.30), axis="Z", region="hull_b",
        smooth=True, close=False)

    # --- two glowing habitat ring bands
    for z in (0.40, 1.30):
        rad = 1.5 - (z - 0.4) * 0.5
        b.lathe(
            [(-0.12, rad), (0.0, rad + 0.12), (0.12, rad), (0.0, rad - 0.04)],
            segments=22, center=(0.0, 0.0, z), axis="Z", region="glow",
            smooth=True, close=False)

    # --- two tiers of radial fin blades
    for tier, (z, base_r, span) in enumerate([(0.20, 1.30, 2.9), (1.35, 1.05, 2.2)]):
        arms = 6 if tier == 0 else 5
        for i in range(arms):
            ang = i * math.tau / arms + tier * 0.4
            c, s = math.cos(ang), math.sin(ang)
            blade = [(base_r, 0.0), (span * 0.75, 0.14), (span, 0.02),
                     (span * 0.75, -0.14), (base_r, -0.07)]
            rot = [(x * c - y * s, x * s + y * c) for (x, y) in blade]
            b.wing(rot, thickness=0.09, z=z, region="wing", taper=0.85)
            tip = [(span * 0.75, 0.0), (span, 0.08), (span + 0.12, 0.0), (span, -0.08)]
            rott = [(x * c - y * s, x * s + y * c) for (x, y) in tip]
            b.wing(rott, thickness=0.10, z=z, region="glow", taper=0.8)


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
    # Organic smooth-lofted hulls (smooth=True, finer segments) legitimately
    # cost a little more than the angular sets; still trivial for MultiMesh.
    "corvette": 1000,
    "destroyer": 1400,
    "cruiser": 1900,
    "battleship": 2800,
    "science": 1100,
    "builder": 1100,
    "station": 2200,
    "stellar_station": 3000,
}
