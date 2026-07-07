"""Void ship set -- crystalline void-touched civilization.

Design language: faceted crystal shards. Blade and diamond profiles lofted
with progressive skew, clusters of counter-angled splinter crystals around
an obsidian core, thin blade fins, glowing crystal veins (glow region) on
shard flanks. No conventional nozzles: engines are glowing crystal tips.
Palette: obsidian hull, deep violet-gray secondary, pale violet accent,
lavender emissives (fleet_void icon family, #a9b4ff).

Ships face +X, up is +Z. Mild asymmetry in shard counts is intentional.
"""

import math

from mathutils import Vector

from shipgen_lib import (
    Palette,
    profile_blade,
    profile_diamond,
)

PALETTE = Palette(
    hull=(0.10, 0.09, 0.14),
    hull_b=(0.21, 0.19, 0.30),
    dark=(0.05, 0.045, 0.08),
    accent=(0.62, 0.60, 0.92),
    metal=(0.30, 0.29, 0.37),
    engine_glow=(0.66, 0.70, 1.00),
    window_glow=(0.72, 0.75, 1.00),
    accent_glow=(0.84, 0.83, 1.00),
    roughness_hull=0.30,
    roughness_metal=0.24,
    panel_contrast=0.05,
    grime=0.0,
)

PREVIEW_ACCENT = (0.72, 0.75, 1.0)


# ---------------------------------------------------------------------------
# Local helpers (void set only)
# ---------------------------------------------------------------------------

def _offset(profile, dy=0.0, dz=0.0):
    return [(y + dy, z + dz) for (y, z) in profile]


def _rotp(profile, roll):
    c, s = math.cos(roll), math.sin(roll)
    return [(y * c - z * s, y * s + z * c) for (y, z) in profile]


def _belly(t, peak=0.45, min_end=0.34, power=1.35):
    """Size envelope along a shard: max at `peak`, `min_end` at both ends."""
    if t <= peak:
        u = t / max(peak, 1e-6)
    else:
        u = (1.0 - t) / max(1.0 - peak, 1e-6)
    return min_end + (1.0 - min_end) * (u ** power)


def _shard(b, x0, x1, y=0.0, z=0.0, w=0.32, h=0.5, lean_y=0.0, lean_z=0.0,
           roll=0.0, peak=0.45, tip=0.4, tail=0.25, nsec=4, region="hull_a",
           waist=0.18, glow_side=0, min_end=0.34, profile="diamond",
           nose_dz=0.0, tail_dz=0.0):
    """Skewed crystal-shard loft along +X with pointed nose and tail.

    lean_y / lean_z progressively offset the cross sections so the shard
    leans; glow_side (+1 starboard-flank / -1 port-flank) tags one flank
    with the emissive vein region."""
    sections = []
    for i in range(nsec):
        t = i / (nsec - 1.0)
        s = _belly(t, peak, min_end)
        if profile == "blade":
            prof = profile_blade(w * s, h * s)
        else:
            prof = profile_diamond(w * s, h * s, waist=waist)
        if roll != 0.0:
            prof = _rotp(prof, roll)
        prof = _offset(prof, dy=y + lean_y * t, dz=z + lean_z * t)
        sections.append((x0 + t * (x1 - x0), prof))
    faces = b.loft(
        sections, region=region,
        nose_point=(x1 + tip, y + lean_y, z + lean_z + nose_dz),
        tail_point=(x0 - tail, y, z + tail_dz))
    if glow_side:
        mid = y + lean_y * 0.5
        glow_faces = []
        for f in faces:
            f.normal_update()
            if (abs(f.normal.y) > 0.45
                    and (f.calc_center_median().y - mid) * glow_side > 0.02):
                glow_faces.append(f)
        b.tag(glow_faces, "glow")
    return faces


def _crystal(b, p0, p1, r0, r1=None, segments=6, frac0=0.22, frac1=0.72,
             region="hull_a", roll=0.0, glow_bands=()):
    """Faceted crystal (elongated bipyramid prism) between two points."""
    p0 = Vector(p0)
    p1 = Vector(p1)
    ax = p1 - p0
    length = ax.length
    if length < 1e-6:
        return []
    ax = ax / length
    ref = Vector((0.0, 0.0, 1.0)) if abs(ax.z) < 0.92 else Vector((0.0, 1.0, 0.0))
    u = ax.cross(ref)
    u.normalize()
    v = ax.cross(u)
    v.normalize()
    if r1 is None:
        r1 = r0 * 0.62
    rings = []
    for frac, radius in ((frac0, r0), (frac1, r1)):
        c = p0 + ax * (length * frac)
        ring = []
        for i in range(segments):
            a = roll + (i / segments) * math.tau
            ring.append(b.bm.verts.new(
                c + u * (math.cos(a) * radius) + v * (math.sin(a) * radius)))
        rings.append(ring)
    va = b.bm.verts.new(p0)
    vb = b.bm.verts.new(p1)
    fans, bands = [], []
    for i in range(segments):
        j = (i + 1) % segments
        try:
            fans.append(b.bm.faces.new((va, rings[0][i], rings[0][j])))
        except ValueError:
            pass
        try:
            bands.append(b.bm.faces.new(
                (rings[0][i], rings[0][j], rings[1][j], rings[1][i])))
        except ValueError:
            pass
        try:
            fans.append(b.bm.faces.new((rings[1][i], rings[1][j], vb)))
        except ValueError:
            pass
    faces = fans + bands
    b.tag(faces, region)
    if glow_bands and bands:
        b.tag([bands[k % len(bands)] for k in glow_bands], "glow")
    return faces


def _arc_lathe(b, profile, center, axis="Z", a0=0.0, a1=math.tau, steps=12,
               region="hull_a", close_ends=True):
    """Partial revolve of a closed (along, radius) profile loop.

    Full circles (a1 - a0 == tau) leave coincident seam verts that commit()
    welds; partial arcs get flat end caps when close_ends is True."""
    cx, cy, cz = center
    rings = []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * (k / steps)
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for along, radius in profile:
            if axis == "Z":
                p = (cx + ca * radius, cy + sa * radius, cz + along)
            elif axis == "Y":
                p = (cx + ca * radius, cy + along, cz + sa * radius)
            else:
                p = (cx + along, cy + ca * radius, cz + sa * radius)
            ring.append(b.bm.verts.new(p))
        rings.append(ring)
    faces = []
    m = len(profile)
    for ra, rb in zip(rings, rings[1:]):
        for i in range(m):
            j = (i + 1) % m
            try:
                faces.append(b.bm.faces.new((ra[i], ra[j], rb[j], rb[i])))
            except ValueError:
                pass
    full = abs((a1 - a0) - math.tau) < 1e-4
    if close_ends and not full:
        try:
            faces.append(b.bm.faces.new(list(reversed(rings[0]))))
            faces.append(b.bm.faces.new(rings[-1]))
        except ValueError:
            pass
    b.tag(faces, region)
    return faces


def _engine_crystal(b, p0, p1, r):
    """Glowing crystal tip in place of a nozzle."""
    _crystal(b, p0, p1, r, r1=r * 0.55, segments=5, frac0=0.30, frac1=0.70,
             region="engine")


def _strut(b, p0, p1, r=0.025, region="dark"):
    """Thin connector so floating shards stay attached."""
    _crystal(b, p0, p1, r, r1=r * 0.9, segments=4, frac0=0.15, frac1=0.85,
             region=region)


def _vein(b, p0, p1, r=0.035):
    """Thin glow ridge crystal half-embedded along a shard flank."""
    _crystal(b, p0, p1, r, r1=r * 0.8, segments=4, frac0=0.2, frac1=0.8,
             region="glow")


def _win_strip(b, x0, x1, y_off, z0, h=0.07, th=0.04, skew=0.0):
    """Small emissive window band proud of a hull flank."""
    outline = [(x0, z0), (x1, z0 + skew), (x1, z0 + skew + h), (x0, z0 + h)]
    b.wing(outline, thickness=th, z=y_off, region="windows", taper=0.85,
           plane="xz")


def _ridge(b, x0, x1, y, z, w, h, region="accent", nose=0.3, tail=0.25,
           lean_z=0.0):
    """Small accent ridge shard along the spine or flank."""
    mid = (x0 + x1) * 0.5
    b.loft(
        [
            (x0, _offset(profile_diamond(w * 0.55, h * 0.55), dy=y, dz=z)),
            (mid, _offset(profile_diamond(w, h), dy=y, dz=z + lean_z * 0.5)),
            (x1, _offset(profile_diamond(w * 0.5, h * 0.5), dy=y, dz=z + lean_z)),
        ],
        region=region,
        nose_point=(x1 + nose, y, z + lean_z),
        tail_point=(x0 - tail, y, z))


def _spire(b, ang_deg, rad, z0, z1, r0, lean=0.2, region="hull_a",
           glow_bands=(), segments=6, roll=0.0):
    """Vertical crystal spire placed radially (stations)."""
    a = math.radians(ang_deg)
    ca, sa = math.cos(a), math.sin(a)
    _crystal(b, (ca * rad, sa * rad, z0),
             (ca * (rad + lean), sa * (rad + lean), z1),
             r0, segments=segments, region=region, roll=roll,
             glow_bands=glow_bands)


# ---------------------------------------------------------------------------
# Ships
# ---------------------------------------------------------------------------

def build_corvette(b):
    """Single main shard + two counter-angled splinters."""
    _shard(b, -1.05, 0.95, w=0.38, h=0.52, lean_z=-0.07, waist=0.22,
           tip=0.42, tail=0.30, nsec=5, glow_side=1, nose_dz=-0.02,
           tail_dz=0.10)

    _ridge(b, -0.75, 0.45, 0.0, 0.20, 0.13, 0.12, nose=0.35, tail=0.30,
           lean_z=-0.04)

    # counter-angled splinters (port rises, starboard dives)
    _crystal(b, (-1.28, 0.30, -0.16), (0.55, 0.46, 0.14), 0.13, roll=0.4,
             region="hull_b", glow_bands=(1,))
    _crystal(b, (-1.08, -0.34, 0.18), (0.75, -0.42, -0.12), 0.11,
             region="hull_b", glow_bands=(4,))
    _crystal(b, (-0.95, -0.05, 0.26), (-0.05, -0.12, 0.50), 0.06,
             region="hull_b")

    # thin blade fins
    b.wing([(-0.50, 0.16), (-1.12, 0.66), (-1.30, 0.60), (-0.90, 0.10)],
           thickness=0.035, z=0.0, region="wing", taper=0.55, plane="xz")
    b.wing([(-0.35, -0.14), (-0.85, -0.52), (-1.02, -0.46), (-0.62, -0.08)],
           thickness=0.035, z=0.06, region="wing", taper=0.55, plane="xz")
    b.wing([(0.12, 0.14), (-0.50, 0.52), (-0.82, 0.48), (-0.30, 0.16)],
           thickness=0.03, z=-0.02, region="wing", taper=0.6)
    b.wing([(0.12, 0.14), (-0.50, 0.52), (-0.82, 0.48), (-0.30, 0.16)],
           thickness=0.03, z=-0.02, region="wing", taper=0.6, flip=True)

    # cockpit window strips
    _win_strip(b, -0.05, 0.42, 0.155, 0.02, h=0.06, th=0.035, skew=0.02)
    _win_strip(b, -0.05, 0.42, -0.155, 0.02, h=0.06, th=0.035, skew=0.02)

    # glow vein ridge on the port lower flank
    _vein(b, (-0.75, -0.17, -0.06), (0.45, -0.14, 0.02))

    # engines: glowing crystal tips
    _engine_crystal(b, (-0.90, 0.10, 0.03), (-1.44, 0.13, 0.09), 0.078)
    _engine_crystal(b, (-0.90, -0.10, 0.03), (-1.44, -0.13, 0.09), 0.078)
    _engine_crystal(b, (-1.00, 0.33, -0.08), (-1.36, 0.35, -0.04), 0.05)


def build_destroyer(b):
    """Twin parallel blades with a bridging core."""
    _shard(b, -1.45, 1.35, y=0.40, z=0.02, w=0.26, h=0.66, profile="blade",
           roll=0.14, tip=0.45, tail=0.32, nsec=5, glow_side=1,
           tail_dz=0.14, nose_dz=-0.04)
    _shard(b, -1.45, 1.25, y=-0.40, z=0.02, w=0.26, h=0.66, profile="blade",
           roll=-0.14, tip=0.45, tail=0.32, nsec=5, glow_side=-1,
           tail_dz=0.14, nose_dz=-0.04)

    # bridging core
    _shard(b, -1.35, 0.30, y=0.0, z=-0.04, w=0.52, h=0.36, waist=0.30,
           tip=0.60, tail=0.38, nsec=4, min_end=0.40, region="hull_b")

    # bridge slabs tying blades to the core
    b.wing([(-0.10, -0.50), (0.32, -0.42), (0.42, 0.42), (0.00, 0.50)],
           thickness=0.05, z=0.10, region="dark", taper=0.85)
    b.wing([(-1.22, -0.50), (-0.80, -0.44), (-0.70, 0.44), (-1.12, 0.50)],
           thickness=0.05, z=-0.08, region="dark", taper=0.85)

    _ridge(b, -0.95, 0.25, 0.0, 0.16, 0.15, 0.11, nose=0.40, tail=0.30)

    # splinters
    _crystal(b, (-0.95, 0.10, 0.22), (0.15, 0.20, 0.48), 0.08,
             region="hull_b", glow_bands=(2,))
    _crystal(b, (-0.75, -0.16, 0.28), (0.30, -0.24, 0.40), 0.065,
             region="hull_b")
    _crystal(b, (-1.15, 0.0, -0.30), (-0.15, 0.05, -0.44), 0.075,
             region="hull_b", roll=0.5)

    # tail fins on each blade + ventral fin
    b.wing([(-0.70, 0.38), (-1.42, 0.92), (-1.62, 0.84), (-1.15, 0.30)],
           thickness=0.03, z=0.40, region="wing", taper=0.5, plane="xz")
    b.wing([(-0.70, 0.38), (-1.42, 0.92), (-1.62, 0.84), (-1.15, 0.30)],
           thickness=0.03, z=-0.40, region="wing", taper=0.5, plane="xz")
    b.wing([(-0.90, -0.20), (-1.50, -0.62), (-1.68, -0.55), (-1.25, -0.14)],
           thickness=0.035, z=0.0, region="wing", taper=0.5, plane="xz")

    _win_strip(b, -0.55, 0.10, 0.205, 0.02, h=0.06, skew=0.015)
    _win_strip(b, -0.55, 0.10, -0.205, 0.02, h=0.06, skew=0.015)

    _vein(b, (-0.90, 0.47, -0.10), (0.60, 0.45, 0.02), r=0.032)
    _vein(b, (-0.90, -0.47, -0.10), (0.60, -0.45, 0.02), r=0.032)

    _engine_crystal(b, (-1.35, 0.42, 0.12), (-1.82, 0.44, 0.18), 0.085)
    _engine_crystal(b, (-1.35, -0.42, 0.12), (-1.82, -0.44, 0.18), 0.085)
    _engine_crystal(b, (-1.50, 0.0, -0.06), (-1.88, 0.0, -0.02), 0.10)


def build_cruiser(b):
    """Shard trident: three forward blades from an obsidian core."""
    _shard(b, -2.15, -0.10, w=0.64, h=0.62, waist=0.28, tip=0.70, tail=0.32,
           nsec=5, region="hull_b", min_end=0.38, tail_dz=0.12)

    # center blade (longest)
    _shard(b, -0.85, 1.90, z=0.06, w=0.28, h=0.78, profile="blade", tip=0.45,
           tail=0.35, nsec=5, glow_side=1, nose_dz=-0.06, tail_dz=0.10)

    # side blades, leaning outward, mild asymmetry in length
    _shard(b, -0.95, 1.30, y=0.28, z=-0.02, w=0.24, h=0.44, lean_y=0.42,
           roll=-0.30, waist=0.20, tip=0.40, tail=0.28, glow_side=1)
    _shard(b, -0.95, 1.22, y=-0.28, z=-0.02, w=0.24, h=0.44, lean_y=-0.42,
           roll=0.30, waist=0.20, tip=0.40, tail=0.28, glow_side=-1)

    _ridge(b, -1.85, -0.35, 0.0, 0.30, 0.14, 0.12, nose=0.45, tail=0.35)

    # dorsal and ventral fins
    b.wing([(-1.45, 0.30), (-2.20, 0.98), (-2.42, 0.90), (-1.90, 0.24)],
           thickness=0.04, z=0.0, region="wing", taper=0.5, plane="xz")
    b.wing([(-1.30, -0.30), (-1.95, -0.85), (-2.15, -0.78), (-1.70, -0.24)],
           thickness=0.04, z=0.0, region="wing", taper=0.5, plane="xz")

    # splinters
    _crystal(b, (-1.35, 0.28, 0.30), (-0.15, 0.42, 0.58), 0.09,
             region="hull_a", glow_bands=(1,))
    _crystal(b, (-1.60, -0.34, -0.22), (-0.45, -0.52, -0.42), 0.08,
             region="hull_b")
    _crystal(b, (0.55, -0.16, 0.28), (1.45, -0.26, 0.44), 0.06,
             region="hull_b")
    _crystal(b, (-2.00, 0.15, -0.35), (-1.00, 0.22, -0.52), 0.07,
             region="hull_b", roll=0.4)

    _win_strip(b, -1.45, -0.70, 0.30, 0.02, h=0.07, skew=0.02)
    _win_strip(b, -1.45, -0.70, -0.30, 0.02, h=0.07, skew=0.02)

    _vein(b, (-0.50, 0.10, 0.00), (1.30, 0.09, 0.10), r=0.03)

    _engine_crystal(b, (-2.05, -0.20, -0.02), (-2.50, -0.22, 0.02), 0.085)
    _engine_crystal(b, (-2.10, 0.0, 0.10), (-2.55, 0.0, 0.14), 0.095)
    _engine_crystal(b, (-2.05, 0.20, -0.02), (-2.50, 0.22, 0.02), 0.085)


def build_battleship(b):
    """Cathedral of shards: great central blade, flanking arrays, spikes."""
    _shard(b, -2.75, 2.65, z=0.12, w=0.36, h=1.05, profile="blade", tip=0.55,
           tail=0.38, nsec=6, glow_side=1, nose_dz=-0.10, tail_dz=0.18,
           peak=0.42)
    # core mass
    _shard(b, -2.60, 0.40, z=-0.16, w=0.88, h=0.64, waist=0.30,
           region="hull_b", tip=0.85, tail=0.45, nsec=5, min_end=0.36,
           tail_dz=0.10)

    # accent rails along the core shoulders
    _ridge(b, -2.00, -0.10, 0.32, 0.10, 0.11, 0.09, nose=0.50, tail=0.40)
    _ridge(b, -2.00, -0.10, -0.32, 0.10, 0.11, 0.09, nose=0.50, tail=0.40)

    # flanking blade arrays (counter-angled, mildly asymmetric)
    _crystal(b, (-2.45, 0.52, -0.10), (0.95, 0.72, 0.18), 0.19, roll=0.3,
             region="hull_a", glow_bands=(1,))
    _crystal(b, (-2.05, 0.85, -0.30), (0.15, 1.02, -0.42), 0.15, roll=0.1,
             region="hull_b")
    _crystal(b, (-1.55, 1.10, 0.05), (-0.25, 1.32, 0.35), 0.11,
             region="hull_b")
    _crystal(b, (-2.45, -0.52, -0.10), (1.05, -0.70, 0.10), 0.19, roll=-0.3,
             region="hull_a", glow_bands=(4,))
    _crystal(b, (-2.05, -0.85, -0.28), (0.05, -1.04, -0.05), 0.15, roll=-0.1,
             region="hull_b")
    _crystal(b, (-1.50, -1.12, 0.02), (-0.15, -1.30, -0.25), 0.11,
             region="hull_b")

    # floating spikes with thin connectors
    _crystal(b, (0.15, 0.16, 0.80), (1.55, 0.24, 1.10), 0.08, region="hull_b")
    _strut(b, (0.80, 0.19, 0.05), (0.85, 0.21, 0.96))
    _crystal(b, (-1.55, -0.24, 0.78), (-0.15, -0.30, 1.04), 0.09,
             region="hull_b")
    _strut(b, (-0.85, -0.26, 0.10), (-0.82, -0.28, 0.92))
    _crystal(b, (-0.85, 0.05, -1.00), (0.55, 0.10, -0.78), 0.10,
             region="hull_b")
    _strut(b, (-0.15, 0.07, -0.42), (-0.12, 0.07, -0.90))

    # tail fins
    b.wing([(-1.90, 0.55), (-2.85, 1.22), (-3.08, 1.12), (-2.42, 0.45)],
           thickness=0.04, z=0.45, region="wing", taper=0.5, plane="xz")
    b.wing([(-1.90, 0.55), (-2.85, 1.22), (-3.08, 1.12), (-2.42, 0.45)],
           thickness=0.04, z=-0.45, region="wing", taper=0.5, plane="xz")
    b.wing([(-1.60, -0.45), (-2.45, -1.05), (-2.68, -0.95), (-2.05, -0.36)],
           thickness=0.04, z=0.0, region="wing", taper=0.5, plane="xz")

    # machinery skirts
    b.wing([(-1.90, -0.34), (-0.40, -0.30), (-0.40, -0.12), (-1.90, -0.16)],
           thickness=0.05, z=0.43, region="greeble", taper=1.0, plane="xz")
    b.wing([(-1.90, -0.34), (-0.40, -0.30), (-0.40, -0.12), (-1.90, -0.16)],
           thickness=0.05, z=-0.43, region="greeble", taper=1.0, plane="xz")

    _win_strip(b, -1.75, -0.55, 0.42, -0.18, h=0.07)
    _win_strip(b, -1.75, -0.55, -0.42, -0.18, h=0.07)

    _vein(b, (-1.80, 0.12, 0.30), (0.60, 0.10, 0.44), r=0.035)
    _vein(b, (-2.00, -0.45, -0.30), (-0.30, -0.43, -0.22), r=0.03)

    # engine crystal cluster
    _engine_crystal(b, (-2.45, 0.0, 0.16), (-3.20, 0.0, 0.24), 0.115)
    _engine_crystal(b, (-2.40, 0.15, -0.12), (-3.10, 0.17, -0.06), 0.095)
    _engine_crystal(b, (-2.40, -0.15, -0.12), (-3.10, -0.17, -0.06), 0.095)
    _engine_crystal(b, (-2.28, 0.55, -0.09), (-2.90, 0.58, -0.03), 0.08)
    _engine_crystal(b, (-2.28, -0.55, -0.09), (-2.90, -0.58, -0.03), 0.08)


def build_science(b):
    """Ring fragment (void icon) orbiting a small core shard."""
    _shard(b, -0.95, 0.95, w=0.36, h=0.46, waist=0.24, tip=0.42, tail=0.30,
           nsec=5, glow_side=1, lean_z=0.05, nose_dz=-0.02)

    _ridge(b, -0.55, 0.35, 0.0, 0.19, 0.10, 0.09, nose=0.30, tail=0.25)

    # horizontal ring fragment (accent, gap facing forward)
    _arc_lathe(b, [(-0.07, 0.99), (0.0, 1.10), (0.08, 0.99), (0.0, 0.87)],
               center=(0.05, 0.0, 0.12), axis="Z", a0=math.radians(35),
               a1=math.radians(325), steps=12, region="accent")
    # vertical orbit fragment over the top
    _arc_lathe(b, [(-0.05, 0.70), (0.0, 0.78), (0.05, 0.70), (0.0, 0.62)],
               center=(0.05, 0.0, 0.12), axis="Y", a0=math.radians(25),
               a1=math.radians(215), steps=9, region="hull_b")

    # connectors so the orbit fragments stay attached
    _strut(b, (0.05, 0.14, 0.10), (0.05, 1.02, 0.13), r=0.035)
    _strut(b, (0.05, -0.14, 0.10), (0.05, -1.02, 0.13), r=0.035)
    _strut(b, (0.05, 0.0, 0.20), (0.05, 0.0, 0.74), r=0.03)

    # sensor crystals
    _crystal(b, (0.85, -0.08, 0.22), (1.30, -0.12, 0.40), 0.05, region="glow")
    _crystal(b, (-0.55, 0.10, -0.20), (0.25, 0.16, -0.38), 0.06,
             region="hull_b")

    _win_strip(b, -0.35, 0.30, 0.16, 0.0, h=0.06, skew=0.02)
    _win_strip(b, -0.35, 0.30, -0.16, 0.0, h=0.06, skew=0.02)

    _engine_crystal(b, (-0.85, 0.0, 0.02), (-1.50, 0.0, 0.08), 0.10)


def build_builder(b):
    """Blunt crystal cluster with extraction prongs."""
    _shard(b, -0.90, 0.40, w=0.62, h=0.58, waist=0.34, peak=0.5, tip=0.50,
           tail=0.32, min_end=0.50, nsec=4)
    _shard(b, -0.70, 0.30, y=0.12, z=0.20, w=0.42, h=0.40, roll=0.55,
           region="hull_b", tip=0.35, tail=0.28, min_end=0.45, waist=0.30)
    _shard(b, -0.80, 0.10, y=-0.16, z=-0.18, w=0.38, h=0.36, roll=-0.45,
           region="hull_b", tip=0.30, tail=0.25, min_end=0.45, waist=0.30)

    # extraction prongs with glowing tips
    _crystal(b, (0.30, 0.22, -0.04), (1.28, 0.42, -0.14), 0.075,
             region="metal")
    _crystal(b, (0.30, -0.22, -0.04), (1.28, -0.42, -0.14), 0.075,
             region="metal")
    _crystal(b, (0.25, 0.0, -0.18), (1.20, 0.0, -0.34), 0.065, region="metal")
    _crystal(b, (1.02, 0.38, -0.12), (1.34, 0.45, -0.16), 0.04, region="glow")
    _crystal(b, (1.02, -0.38, -0.12), (1.34, -0.45, -0.16), 0.04,
             region="glow")
    _crystal(b, (0.95, 0.0, -0.30), (1.26, 0.0, -0.38), 0.035, region="glow")

    # machinery skirts
    b.wing([(-0.80, -0.10), (0.05, -0.06), (0.05, 0.12), (-0.80, 0.08)],
           thickness=0.05, z=0.30, region="greeble", taper=1.0, plane="xz")
    b.wing([(-0.80, -0.10), (0.05, -0.06), (0.05, 0.12), (-0.80, 0.08)],
           thickness=0.05, z=-0.30, region="greeble", taper=1.0, plane="xz")

    # top crystal cluster
    _crystal(b, (-0.55, 0.05, 0.25), (0.10, 0.10, 0.55), 0.07,
             region="hull_a", glow_bands=(2,))
    _crystal(b, (-0.35, -0.12, 0.28), (0.05, -0.18, 0.48), 0.05,
             region="hull_b")

    _win_strip(b, 0.0, 0.35, 0.20, -0.02, h=0.055, skew=-0.01)
    _win_strip(b, 0.0, 0.35, -0.20, -0.02, h=0.055, skew=-0.01)

    _engine_crystal(b, (-0.95, 0.13, 0.02), (-1.32, 0.15, 0.06), 0.08)
    _engine_crystal(b, (-0.95, -0.13, 0.02), (-1.32, -0.15, 0.06), 0.08)


def build_station(b):
    """Vertical crystal spire cluster growing from a faceted base ring."""
    # faceted lavender base ring (void icon)
    _arc_lathe(b, [(-0.16, 1.52), (0.02, 1.74), (0.16, 1.50), (0.0, 1.30)],
               center=(0.0, 0.0, -0.85), axis="Z", a0=0.0, a1=math.tau,
               steps=8, region="accent", close_ends=False)

    # grand central spire
    _crystal(b, (0.0, 0.0, -1.75), (0.0, 0.0, 1.95), 0.46, r1=0.30,
             segments=6, frac0=0.30, frac1=0.72, region="hull_a",
             glow_bands=(1, 4))

    # secondary spires, uneven ring (mild asymmetry)
    _spire(b, 30, 0.70, -1.30, 1.15, 0.20, lean=0.22, region="hull_b",
           glow_bands=(0,))
    _spire(b, 100, 0.75, -1.20, 0.85, 0.17, lean=0.18, region="hull_b")
    _spire(b, 165, 0.68, -1.35, 1.35, 0.22, lean=0.15, region="hull_a",
           glow_bands=(3,))
    _spire(b, 250, 0.72, -1.25, 1.00, 0.18, lean=0.25, region="hull_b")
    _spire(b, 315, 0.66, -1.30, 0.70, 0.15, lean=0.20, region="hull_b")

    # spokes tying the ring to the spire cluster
    for ang in (45.0, 135.0, 225.0, 315.0):
        a = math.radians(ang)
        _strut(b, (math.cos(a) * 0.28, math.sin(a) * 0.28, -0.85),
               (math.cos(a) * 1.58, math.sin(a) * 1.58, -0.85), r=0.06,
               region="dark")

    # window rings around the grand spire
    _arc_lathe(b, [(-0.06, 0.35), (0.0, 0.43), (0.06, 0.35), (0.0, 0.30)],
               center=(0.0, 0.0, 0.30), axis="Z", steps=6, region="windows",
               close_ends=False)
    _arc_lathe(b, [(-0.05, 0.44), (0.0, 0.50), (0.05, 0.44), (0.0, 0.38)],
               center=(0.0, 0.0, -0.35), axis="Z", steps=6, region="windows",
               close_ends=False)

    # floating glow crystals with thin connectors
    _crystal(b, (0.95, 0.42, 0.55), (1.22, 0.52, 1.00), 0.06, region="glow")
    _strut(b, (0.66, 0.36, 0.40), (1.02, 0.45, 0.72), r=0.025)
    _crystal(b, (-0.85, -0.55, 0.30), (-1.08, -0.72, 0.75), 0.055,
             region="glow")
    _strut(b, (-0.42, -0.60, 0.10), (-0.92, -0.60, 0.48), r=0.025)


def build_stellar_station(b):
    """Grand shard cathedral with a lathed void ring around the spire."""
    # grand lavender ring
    _arc_lathe(b, [(-0.18, 2.28), (0.03, 2.60), (0.18, 2.26), (0.0, 1.98)],
               center=(0.0, 0.0, 0.15), axis="Z", a0=0.0, a1=math.tau,
               steps=12, region="accent", close_ends=False)
    # vertical orbit ring threading over the cathedral
    _arc_lathe(b, [(-0.07, 1.46), (0.0, 1.60), (0.07, 1.46), (0.0, 1.32)],
               center=(0.0, 0.0, 0.15), axis="Y", a0=0.0, a1=math.tau,
               steps=12, region="hull_b", close_ends=False)

    # grand central spire
    _crystal(b, (0.0, 0.0, -2.30), (0.0, 0.0, 2.50), 0.52, r1=0.36,
             segments=6, frac0=0.30, frac1=0.72, region="hull_a",
             glow_bands=(1, 4))

    # faceted base bulk
    b.lathe([(-0.55, 0.02), (-0.22, 0.78), (0.08, 0.98), (0.38, 0.72),
             (0.62, 0.02)],
            segments=8, center=(0.0, 0.0, -1.40), axis="Z", region="hull_b",
            smooth=False)

    # cathedral of secondary spires
    _spire(b, 20, 0.85, -1.75, 1.55, 0.22, lean=0.25, region="hull_b",
           glow_bands=(2,))
    _spire(b, 80, 0.90, -1.60, 1.10, 0.18, lean=0.20, region="hull_b")
    _spire(b, 140, 0.82, -1.80, 1.80, 0.25, lean=0.18, region="hull_a",
           glow_bands=(5,))
    _spire(b, 200, 0.88, -1.65, 1.25, 0.19, lean=0.28, region="hull_b")
    _spire(b, 260, 0.84, -1.70, 0.95, 0.16, lean=0.22, region="hull_b")
    _spire(b, 320, 0.86, -1.72, 1.45, 0.21, lean=0.20, region="hull_a",
           glow_bands=(0,))

    # spokes to the grand ring
    for ang in (45.0, 135.0, 225.0, 315.0):
        a = math.radians(ang)
        _strut(b, (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.15),
               (math.cos(a) * 2.15, math.sin(a) * 2.15, 0.15), r=0.07,
               region="dark")
    # struts to the vertical ring
    _strut(b, (0.45, 0.0, 0.15), (1.45, 0.0, 0.15), r=0.05)
    _strut(b, (-0.45, 0.0, 0.15), (-1.45, 0.0, 0.15), r=0.05)

    # window rings
    _arc_lathe(b, [(-0.06, 0.44), (0.0, 0.52), (0.06, 0.44), (0.0, 0.38)],
               center=(0.0, 0.0, 0.65), axis="Z", steps=6, region="windows",
               close_ends=False)
    _arc_lathe(b, [(-0.06, 0.50), (0.0, 0.58), (0.06, 0.50), (0.0, 0.44)],
               center=(0.0, 0.0, -0.55), axis="Z", steps=6, region="windows",
               close_ends=False)

    # floating shards above with thin connectors
    _crystal(b, (0.45, 0.35, 1.95), (1.00, 0.65, 2.45), 0.08,
             region="hull_b", glow_bands=(1,))
    _strut(b, (0.20, 0.15, 1.70), (0.60, 0.42, 2.10), r=0.025)
    _crystal(b, (-0.75, -0.30, 1.75), (-1.25, -0.55, 2.20), 0.07,
             region="hull_b")
    _strut(b, (-0.22, -0.08, 1.55), (-0.85, -0.35, 1.90), r=0.025)

    # glow crystals studding the grand ring
    for ang in (30.0, 120.0, 210.0, 300.0):
        a = math.radians(ang)
        _crystal(b, (math.cos(a) * 2.28, math.sin(a) * 2.28, 0.28),
                 (math.cos(a) * 2.28, math.sin(a) * 2.28, 0.78), 0.07,
                 segments=5, region="glow")


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
