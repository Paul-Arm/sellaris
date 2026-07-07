"""Shared library for procedural ship generation in headless Blender.

Usage: imported by generate.py which runs inside Blender 5.x
(`blender --background --python tools/shipgen/generate.py -- --set <id>`).

Design goals:
  * Custom geometry (lofted hulls from bespoke cross-section profiles,
    polygon-outline wings, lathed nozzles/dishes, insets/bevels) instead of
    stock primitives.
  * One trim-sheet texture atlas per ship set (albedo + emission + ORM),
    painted with numpy — no Cycles baking needed, deterministic and fast.
  * Medium poly budgets (600-2800 tris per ship) so MultiMesh can draw
    thousands of instances.
  * Ships face +X, up is +Z in Blender; the glTF exporter converts to
    Godot's +X-forward / +Y-up convention automatically.
"""

import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# Trim sheet regions (u0, v0, u1, v1) in UV space. The texture painter and the
# UV mapper share this table; keep margins so bilinear filtering never bleeds
# between regions.
# ---------------------------------------------------------------------------

TRIM_REGIONS = {
    "hull_a": (0.00, 0.50, 0.50, 1.00),   # primary plating
    "hull_b": (0.50, 0.50, 1.00, 1.00),   # secondary / darker plating
    "wing": (0.00, 0.25, 0.50, 0.50),     # wing / fin panels
    "accent": (0.50, 0.375, 1.00, 0.50),  # painted accent band
    "dark": (0.50, 0.25, 1.00, 0.375),    # dark structural metal / vents
    "engine": (0.00, 0.125, 0.25, 0.25),  # engine glow (strong emission)
    "windows": (0.25, 0.125, 0.50, 0.25), # window strips (emission dots)
    "glow": (0.50, 0.125, 0.75, 0.25),    # accent emission (veins / strips)
    "metal": (0.75, 0.125, 1.00, 0.25),   # bare metal, high metallic
    "greeble": (0.00, 0.00, 1.00, 0.125), # machinery strip
}

REGION_MARGIN = 0.012

ATLAS_SIZE = 1024


class Palette:
    """Set-specific colors and surface parameters (linear-ish sRGB floats)."""

    def __init__(
        self,
        hull=(0.62, 0.65, 0.70),
        hull_b=(0.42, 0.45, 0.50),
        dark=(0.16, 0.17, 0.20),
        accent=(0.91, 0.31, 0.31),
        metal=(0.55, 0.55, 0.58),
        engine_glow=(0.55, 0.85, 1.00),
        window_glow=(1.00, 0.92, 0.75),
        accent_glow=None,
        roughness_hull=0.62,
        roughness_metal=0.35,
        panel_contrast=0.10,
        grime=0.06,
    ):
        self.hull = hull
        self.hull_b = hull_b
        self.dark = dark
        self.accent = accent
        self.metal = metal
        self.engine_glow = engine_glow
        self.window_glow = window_glow
        self.accent_glow = accent_glow if accent_glow is not None else engine_glow
        self.roughness_hull = roughness_hull
        self.roughness_metal = roughness_metal
        self.panel_contrast = panel_contrast
        self.grime = grime


# ---------------------------------------------------------------------------
# Profile helpers — 2D cross sections in the YZ plane, CCW point lists.
# All profiles get resampled to a common vertex count before lofting, so any
# custom polygon works.
# ---------------------------------------------------------------------------

def profile_ngon(points):
    """Pass-through for an explicit list of (y, z) tuples."""
    return [tuple(p) for p in points]


def profile_chine(width, height, chine=0.35, top_bias=0.55, flat_bottom=0.3):
    """Faceted 'hull with chine line' profile: flat-ish deck, angled sides.

    chine: how far out the widest point sits below the midline (0..1).
    top_bias: fraction of height above the midline.
    """
    hw = width * 0.5
    top = height * top_bias
    bot = -height * (1.0 - top_bias)
    fb = hw * flat_bottom
    return [
        (fb, bot), (hw * 0.92, bot * (1.0 - chine * 0.5)), (hw, bot * chine * 0.2),
        (hw * 0.72, top * 0.72), (hw * 0.28, top), (-hw * 0.28, top), (-hw * 0.72, top * 0.72),
        (-hw, bot * chine * 0.2), (-hw * 0.92, bot * (1.0 - chine * 0.5)), (-fb, bot),
    ]


def profile_diamond(width, height, waist=0.18):
    hw, hh = width * 0.5, height * 0.5
    w = waist
    return [
        (0.0, -hh), (hw * 0.55, -hh * 0.45), (hw, -hh * w), (hw, hh * w),
        (hw * 0.55, hh * 0.45), (0.0, hh), (-hw * 0.55, hh * 0.45), (-hw, hh * w),
        (-hw, -hh * w), (-hw * 0.55, -hh * 0.45),
    ]


def profile_hex(width, height, squash=0.7):
    hw, hh = width * 0.5, height * 0.5
    return [
        (hw * squash, -hh), (hw, 0.0), (hw * squash, hh),
        (-hw * squash, hh), (-hw, 0.0), (-hw * squash, -hh),
    ]


def profile_lens(width, height, n=12, bulge=1.0):
    """Smooth lens / ellipse-ish profile for organic hulls."""
    pts = []
    hw, hh = width * 0.5, height * 0.5
    for i in range(n):
        a = (i / n) * math.tau
        y = math.sin(a) * hw
        z = -math.cos(a) * hh * (1.0 + 0.18 * bulge * math.cos(a))
        pts.append((y, z))
    return pts


def profile_blade(width, height, edge=0.06):
    """Thin vertical blade with a sharp top ridge (crystal / fin hulls)."""
    hw, hh = width * 0.5, height * 0.5
    return [
        (0.0, -hh), (hw, -hh * 0.35), (hw * edge * 6.0, hh * 0.35), (0.0, hh),
        (-hw * edge * 6.0, hh * 0.35), (-hw, -hh * 0.35),
    ]


def _resample_closed(points, n):
    """Resample a closed polygon to n points by arc length."""
    pts = [Vector((p[0], p[1])) for p in points]
    count = len(pts)
    seg_lengths = [(pts[(i + 1) % count] - pts[i]).length for i in range(count)]
    total = sum(seg_lengths) or 1.0
    result = []
    for k in range(n):
        target = (k / n) * total
        acc = 0.0
        for i in range(count):
            if acc + seg_lengths[i] >= target or i == count - 1:
                t = 0.0 if seg_lengths[i] == 0 else (target - acc) / seg_lengths[i]
                p = pts[i].lerp(pts[(i + 1) % count], t)
                result.append((p.x, p.y))
                break
            acc += seg_lengths[i]
    return result


def blend_profiles(a, b, t, n=None):
    n = n or max(len(a), len(b))
    ra, rb = _resample_closed(a, n), _resample_closed(b, n)
    return [(ra[i][0] * (1 - t) + rb[i][0] * t, ra[i][1] * (1 - t) + rb[i][1] * t) for i in range(n)]


# ---------------------------------------------------------------------------
# Geometry builders
# ---------------------------------------------------------------------------

class ShipBuilder:
    """Wraps a bmesh under construction plus per-face trim region tags."""

    def __init__(self, name, rng=None):
        self.name = name
        self.bm = bmesh.new()
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")
        self._face_regions = {}  # face -> (region, axis, rotate90)
        self.rng = rng or random.Random(name)

    # -- lofting ------------------------------------------------------------

    def loft(self, sections, region="hull_a", cap_nose=True, cap_tail=True,
             smooth=False, nose_point=None, tail_point=None):
        """sections: list of (x, profile_points). Profiles are resampled to a
        common count. Returns list of created faces."""
        n = max(len(p) for _, p in sections)
        n = max(n, 6)
        rings = []
        for x, pts in sections:
            rs = _resample_closed(pts, n)
            ring = [self.bm.verts.new((x, y, z)) for (y, z) in rs]
            rings.append(ring)
        faces = []
        for ra, rb in zip(rings, rings[1:]):
            for i in range(n):
                try:
                    f = self.bm.faces.new((ra[i], ra[(i + 1) % n], rb[(i + 1) % n], rb[i]))
                    f.smooth = smooth
                    faces.append(f)
                except ValueError:
                    pass  # degenerate (duplicate) face — skip
        if cap_nose:
            faces += self._cap(rings[-1], nose_point, smooth, flip=False)
        if cap_tail:
            faces += self._cap(rings[0], tail_point, smooth, flip=True)
        self.tag(faces, region)
        return faces

    def _cap(self, ring, apex, smooth, flip):
        faces = []
        if apex is not None:
            av = self.bm.verts.new(apex)
            count = len(ring)
            for i in range(count):
                a, b = ring[i], ring[(i + 1) % count]
                order = (b, a, av) if flip else (a, b, av)
                try:
                    f = self.bm.faces.new(order)
                    f.smooth = smooth
                    faces.append(f)
                except ValueError:
                    pass
        else:
            try:
                f = self.bm.faces.new(list(reversed(ring)) if flip else ring)
                f.smooth = smooth
                faces.append(f)
            except ValueError:
                pass
        return faces

    # -- wings / fins ---------------------------------------------------------

    def wing(self, outline, thickness=0.08, z=0.0, region="wing", taper=0.55,
             plane="xy", flip=False):
        """Prism from a custom closed outline.

        outline: [(x, y)] in the given plane ('xy' horizontal wing,
        'xz' vertical fin). taper scales the far side (top for xy) inward for
        a chamfered slab look instead of a plain box. Returns faces."""
        pts = [Vector((p[0], p[1])) for p in outline]
        center = sum(pts, Vector((0, 0))) / len(pts)
        ht = thickness * 0.5

        def to3(p, off):
            if plane == "xy":
                return (p.x, p.y if not flip else -p.y, z + off)
            return (p.x, z + off if not flip else z - off, p.y)

        top_ring, bot_ring = [], []
        for p in pts:
            pt = center.lerp(p, taper) if taper != 1.0 else p
            top_ring.append(self.bm.verts.new(to3(pt, ht)))
            bot_ring.append(self.bm.verts.new(to3(p, -ht)))
        faces = []
        count = len(pts)
        for i in range(count):
            j = (i + 1) % count
            try:
                faces.append(self.bm.faces.new((bot_ring[i], bot_ring[j], top_ring[j], top_ring[i])))
            except ValueError:
                pass
        try:
            faces.append(self.bm.faces.new(list(reversed(top_ring))))
            faces.append(self.bm.faces.new(bot_ring))
        except ValueError:
            pass
        if flip ^ (plane == "xz"):
            pass
        self.tag(faces, region)
        return faces

    # -- lathe ----------------------------------------------------------------

    def lathe(self, profile, segments=10, center=(0, 0, 0), axis="X",
              region="metal", smooth=True, close=True):
        """Revolve a custom (t, r) profile around an axis through `center`.

        profile: [(along, radius)] pairs; `along` runs along the axis."""
        cx, cy, cz = center
        rings = []
        for along, radius in profile:
            ring = []
            for i in range(segments):
                a = (i / segments) * math.tau
                if axis == "X":
                    v = (cx + along, cy + math.cos(a) * radius, cz + math.sin(a) * radius)
                elif axis == "Z":
                    v = (cx + math.cos(a) * radius, cy + math.sin(a) * radius, cz + along)
                else:
                    v = (cx + math.cos(a) * radius, cy + along, cz + math.sin(a) * radius)
                ring.append(self.bm.verts.new(v))
            rings.append(ring)
        faces = []
        for ra, rb in zip(rings, rings[1:]):
            for i in range(segments):
                j = (i + 1) % segments
                try:
                    f = self.bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
                    f.smooth = smooth
                    faces.append(f)
                except ValueError:
                    pass
        if close:
            for ring, flip in ((rings[0], False), (rings[-1], True)):
                if len({v.co[:] for v in ring}) < 3:
                    continue
                try:
                    f = self.bm.faces.new(ring if flip else list(reversed(ring)))
                    f.smooth = False
                    faces.append(f)
                except ValueError:
                    pass
        self.tag(faces, region)
        return faces

    # -- detail ops -------------------------------------------------------------

    def inset(self, faces, thickness=0.04, depth=-0.03, region=None):
        """Inset faces and push them in/out; returns the new inner faces."""
        res = bmesh.ops.inset_region(self.bm, faces=list(faces), thickness=thickness,
                                     depth=depth, use_even_offset=True)
        inner = [f for f in res.get("faces", []) if f.is_valid]
        # inset_region returns the border faces; the originals become the inner
        inner_faces = [f for f in faces if f.is_valid]
        if region:
            self.tag(inner_faces, region)
            self.tag(inner, self._face_regions.get(faces[0], ("hull_a",))[0] if faces else "hull_a")
        return inner_faces

    def bevel(self, offset=0.02, segments=1, angle_deg=38.0):
        """Bevel sharp edges of the whole mesh for a chamfered hard-surface look."""
        edges = [e for e in self.bm.edges
                 if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(angle_deg)]
        if not edges:
            return
        res = bmesh.ops.bevel(self.bm, geom=edges, offset=offset, segments=segments,
                              profile=0.7, affect="EDGES", clamp_overlap=True)
        # new bevel faces inherit the region of an adjacent tagged face
        for f in res.get("faces", []):
            if f not in self._face_regions:
                for e in f.edges:
                    for nf in e.link_faces:
                        if nf in self._face_regions:
                            self._face_regions[f] = self._face_regions[nf]
                            break
                    if f in self._face_regions:
                        break

    def mirror_y(self):
        """Mirror everything across the XZ plane (port/starboard symmetry)."""
        geom = list(self.bm.verts) + list(self.bm.edges) + list(self.bm.faces)
        res = bmesh.ops.mirror(self.bm, geom=geom, matrix=Matrix.Identity(4),
                               merge_dist=0.0005, axis="Y")
        new_faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
        # mirrored faces keep their source's trim region
        src_faces = [f for f in self._face_regions if f.is_valid]
        for f in new_faces:
            if f not in self._face_regions:
                best, best_d = None, 1e9
                fc = f.calc_center_median()
                mc = Vector((fc.x, -fc.y, fc.z))
                for sf in src_faces:
                    d = (sf.calc_center_median() - mc).length_squared
                    if d < best_d:
                        best, best_d = sf, d
                if best is not None:
                    self._face_regions[f] = self._face_regions[best]
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))

    def translate(self, faces, offset):
        verts = {v for f in faces for v in f.verts}
        bmesh.ops.translate(self.bm, verts=list(verts), vec=Vector(offset))

    def scale_all(self, factor):
        bmesh.ops.scale(self.bm, verts=list(self.bm.verts),
                        vec=Vector((factor, factor, factor)))

    def scale_axis(self, factor, axis=0):
        """Non-uniform scale on one axis (0=X,1=Y,2=Z) about the origin.

        Handy to stretch a whole ship to a length target after building
        without re-tuning every coordinate."""
        vec = [1.0, 1.0, 1.0]
        vec[axis] = factor
        bmesh.ops.scale(self.bm, verts=list(self.bm.verts), vec=Vector(vec))

    # -- trim tagging / UV mapping ------------------------------------------------

    def tag(self, faces, region, axis="auto", rot90=False):
        for f in faces:
            self._face_regions[f] = (region, axis, rot90)

    def _project_face_uv(self, face, axis):
        n = face.normal
        if axis == "auto":
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            if az >= ax and az >= ay:
                axis = "Z"
            elif ay >= ax:
                axis = "Y"
            else:
                axis = "X"
        coords = []
        for loop in face.loops:
            co = loop.vert.co
            if axis == "Z":
                coords.append((co.x, co.y))
            elif axis == "Y":
                coords.append((co.x, co.z))
            else:
                coords.append((co.y, co.z))
        return coords

    def apply_uvs(self, texel_density=0.55):
        """Box-project every tagged face into its trim region.

        Coordinates wrap inside the region via modulo so long hulls reuse the
        plating texture; texel_density scales world units -> region span."""
        for face in self.bm.faces:
            if not face.is_valid:
                continue
            region, axis, rot90 = self._face_regions.get(face, ("hull_a", "auto", False))
            u0, v0, u1, v1 = TRIM_REGIONS[region]
            u0 += REGION_MARGIN
            v0 += REGION_MARGIN
            u1 -= REGION_MARGIN
            v1 -= REGION_MARGIN
            du, dv = u1 - u0, v1 - v0
            coords = self._project_face_uv(face, axis)
            if rot90:
                coords = [(c[1], c[0]) for c in coords]
            # normalize into a repeating cell, then fold (mirror-wrap) so faces
            # never cross the region border even when larger than one cell
            for loop, (cu, cv) in zip(face.loops, coords):
                fu = (cu * texel_density / max(du, 1e-6)) % 2.0
                fv = (cv * texel_density / max(dv, 1e-6)) % 2.0
                if fu > 1.0:
                    fu = 2.0 - fu
                if fv > 1.0:
                    fv = 2.0 - fv
                loop[self.uv_layer].uv = (u0 + fu * du, v0 + fv * dv)

    # -- finalize -------------------------------------------------------------

    def commit(self, material, weld_dist=0.0004, mark_sharp_angle=44.0):
        bmesh.ops.remove_doubles(self.bm, verts=list(self.bm.verts), dist=weld_dist)
        bmesh.ops.dissolve_degenerate(self.bm, dist=0.0002, edges=list(self.bm.edges))
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        self.apply_uvs()
        for e in self.bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(mark_sharp_angle):
                e.smooth = False
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        obj.data.materials.append(material)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ---------------------------------------------------------------------------
# Texture painting (numpy -> bpy.data.images -> PNG)
# ---------------------------------------------------------------------------

def _region_px(region, size):
    u0, v0, u1, v1 = TRIM_REGIONS[region]
    return (int(u0 * size), int(v0 * size), int(u1 * size), int(v1 * size))


def _value_noise(shape, rng, octaves=((8, 0.5), (32, 0.3), (128, 0.2))):
    h, w = shape
    out = np.zeros(shape, dtype=np.float32)
    for cells, weight in octaves:
        g = rng.random((cells + 1, cells + 1)).astype(np.float32)
        ys = np.linspace(0, cells, h, endpoint=False)
        xs = np.linspace(0, cells, w, endpoint=False)
        y0 = ys.astype(int); x0 = xs.astype(int)
        fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x0 + 1)]
        c = g[np.ix_(y0 + 1, x0)]; d = g[np.ix_(y0 + 1, x0 + 1)]
        out += weight * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
    return out


def _bsp_panels(x0, y0, x1, y1, rng, min_size=28, depth=0):
    """Recursive rectangle splits -> list of panel rects."""
    w, h = x1 - x0, y1 - y0
    if depth > 6 or (w < min_size * 2 and h < min_size * 2) or rng.random() < 0.12 * depth:
        return [(x0, y0, x1, y1)]
    if w >= h:
        split = int(x0 + w * rng.uniform(0.35, 0.65))
        return (_bsp_panels(x0, y0, split, y1, rng, min_size, depth + 1)
                + _bsp_panels(split, y0, x1, y1, rng, min_size, depth + 1))
    split = int(y0 + h * rng.uniform(0.35, 0.65))
    return (_bsp_panels(x0, y0, x1, split, rng, min_size, depth + 1)
            + _bsp_panels(x0, split, x1, y1, rng, min_size, depth + 1))


def _paint_plating(albedo, rough, region, base_color, rng, contrast=0.10,
                   grime=0.06, seam_dark=0.55, base_rough=0.6, size=ATLAS_SIZE):
    x0, y0, x1, y1 = _region_px(region, size)
    panels = _bsp_panels(x0, y0, x1, y1, rng)
    base = np.array(base_color, dtype=np.float32)
    for (px0, py0, px1, py1) in panels:
        jitter = 1.0 + rng.uniform(-contrast, contrast)
        albedo[py0:py1, px0:px1, :3] = base[None, None, :] * jitter
        rough[py0:py1, px0:px1] = np.clip(base_rough + rng.uniform(-0.08, 0.10), 0.05, 0.98)
        # seams
        albedo[py0:py0 + 2, px0:px1, :3] *= seam_dark
        albedo[py1 - 1:py1, px0:px1, :3] *= seam_dark
        albedo[py0:py1, px0:px0 + 2, :3] *= seam_dark
        albedo[py0:py1, px1 - 1:px1, :3] *= seam_dark
        # bevel highlight on one edge
        albedo[py0 + 2:py0 + 3, px0 + 2:px1 - 2, :3] = np.clip(
            albedo[py0 + 2:py0 + 3, px0 + 2:px1 - 2, :3] * 1.28, 0, 1)
        # sparse tiny details: bolts / hatches
        if rng.random() < 0.45 and (px1 - px0) > 40 and (py1 - py0) > 40:
            hx = rng.integers(px0 + 8, px1 - 16)
            hy = rng.integers(py0 + 8, py1 - 16)
            albedo[hy:hy + 6, hx:hx + 10, :3] *= 0.72
            rough[hy:hy + 6, hx:hx + 10] = 0.85
    # noise grime + streaks
    h, w = y1 - y0, x1 - x0
    noise = _value_noise((h, w), rng)
    albedo[y0:y1, x0:x1, :3] *= (1.0 - grime + noise[..., None] * grime * 2.0) * 0.5 + 0.5
    streaks = _value_noise((h, w), rng, octaves=((4, 0.4), (16, 0.6)))
    streak_mask = (streaks > 0.62).astype(np.float32) * 0.06
    albedo[y0:y1, x0:x1, :3] *= (1.0 - streak_mask[..., None])


def _paint_flat(img, region, color, size=ATLAS_SIZE):
    x0, y0, x1, y1 = _region_px(region, size)
    img[y0:y1, x0:x1, :3] = np.array(color, dtype=np.float32)[None, None, :]


def _paint_engine_glow(emission, albedo, region, glow_color, rng, size=ATLAS_SIZE):
    x0, y0, x1, y1 = _region_px(region, size)
    h, w = y1 - y0, x1 - x0
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cy, cx = h / 2.0, w / 2.0
    d = np.sqrt(((yy - cy) / (h * 0.5)) ** 2 + ((xx - cx) / (w * 0.5)) ** 2)
    core = np.clip(1.0 - d, 0.0, 1.0) ** 1.6
    col = np.array(glow_color, dtype=np.float32)
    white = np.array((1.0, 1.0, 1.0), dtype=np.float32)
    glow = core[..., None] * col[None, None, :] + (np.clip(1.0 - d * 1.6, 0, 1) ** 3.2)[..., None] * white * 0.9
    emission[y0:y1, x0:x1, :3] = np.clip(glow, 0, 1)
    albedo[y0:y1, x0:x1, :3] = np.clip(glow * 0.6 + 0.08, 0, 1)


def _paint_windows(emission, albedo, region, window_color, dark_color, rng, size=ATLAS_SIZE):
    x0, y0, x1, y1 = _region_px(region, size)
    albedo[y0:y1, x0:x1, :3] = np.array(dark_color, dtype=np.float32) * 0.8
    emission[y0:y1, x0:x1, :3] = 0.0
    col = np.array(window_color, dtype=np.float32)
    rows = 7
    for r in range(rows):
        wy = int(y0 + (r + 0.5) / rows * (y1 - y0))
        x = x0 + 6
        while x < x1 - 10:
            wlen = int(rng.integers(4, 14))
            if rng.random() < 0.68:
                bright = rng.uniform(0.55, 1.0)
                emission[wy:wy + 3, x:x + wlen, :3] = col * bright
                albedo[wy:wy + 3, x:x + wlen, :3] = col * bright * 0.5
            x += wlen + int(rng.integers(4, 12))


def _paint_glow_strips(emission, albedo, region, glow_color, rng, veins=False, size=ATLAS_SIZE):
    x0, y0, x1, y1 = _region_px(region, size)
    h, w = y1 - y0, x1 - x0
    col = np.array(glow_color, dtype=np.float32)
    emission[y0:y1, x0:x1, :3] = 0.0
    albedo[y0:y1, x0:x1, :3] = 0.04
    if veins:
        noise = _value_noise((h, w), rng, octaves=((6, 0.55), (24, 0.45)))
        band = np.exp(-((noise - 0.5) ** 2) / 0.004)
        emission[y0:y1, x0:x1, :3] = band[..., None] * col[None, None, :]
        albedo[y0:y1, x0:x1, :3] = np.clip(band[..., None] * col * 0.4 + 0.05, 0, 1)
    else:
        n_strips = 4
        for s in range(n_strips):
            sy = int(y0 + (s + 0.5) / n_strips * h)
            th = max(2, h // 18)
            yy = np.arange(y0, y1)[:, None].astype(np.float32)
            fall = np.exp(-((yy - sy) ** 2) / (2.0 * (th * 1.5) ** 2))
            emission[y0:y1, x0:x1, :3] += fall[..., None] * col[None, None, :] * 0.9
        emission[y0:y1, x0:x1, :3] = np.clip(emission[y0:y1, x0:x1, :3], 0, 1)
        albedo[y0:y1, x0:x1, :3] = np.clip(emission[y0:y1, x0:x1, :3] * 0.4 + 0.05, 0, 1)


def _paint_greeble(albedo, rough, metal, region, dark_color, metal_color, rng, size=ATLAS_SIZE):
    x0, y0, x1, y1 = _region_px(region, size)
    albedo[y0:y1, x0:x1, :3] = np.array(dark_color, dtype=np.float32)
    rough[y0:y1, x0:x1] = 0.8
    x = x0
    while x < x1 - 8:
        w = int(rng.integers(6, 28))
        h = int(rng.integers(int((y1 - y0) * 0.3), int((y1 - y0) * 0.9)))
        gy = int(rng.integers(y0, max(y0 + 1, y1 - h)))
        shade = rng.uniform(0.6, 1.6)
        block_col = np.array(metal_color if rng.random() < 0.4 else dark_color, dtype=np.float32) * shade
        albedo[gy:gy + h, x:x + w, :3] = np.clip(block_col, 0, 1)
        if rng.random() < 0.4:
            metal[gy:gy + h, x:x + w] = 1.0
            rough[gy:gy + h, x:x + w] = 0.35
        albedo[gy:gy + 1, x:x + w, :3] *= 1.3
        albedo[gy + h - 1:gy + h, x:x + w, :3] *= 0.5
        x += w + int(rng.integers(2, 8))


def paint_atlas(palette, seed, size=ATLAS_SIZE):
    """Paint albedo/emission/ORM trim sheets; returns dict of float arrays."""
    rng = np.random.default_rng(seed)
    albedo = np.zeros((size, size, 4), dtype=np.float32)
    albedo[..., 3] = 1.0
    emission = np.zeros((size, size, 4), dtype=np.float32)
    emission[..., 3] = 1.0
    rough = np.full((size, size), 0.6, dtype=np.float32)
    metal = np.zeros((size, size), dtype=np.float32)

    _paint_plating(albedo, rough, "hull_a", palette.hull, rng,
                   contrast=palette.panel_contrast, grime=palette.grime,
                   base_rough=palette.roughness_hull)
    _paint_plating(albedo, rough, "hull_b", palette.hull_b, rng,
                   contrast=palette.panel_contrast * 1.3, grime=palette.grime * 1.4,
                   base_rough=min(palette.roughness_hull + 0.08, 0.95))
    _paint_plating(albedo, rough, "wing", palette.hull, rng,
                   contrast=palette.panel_contrast * 0.8, grime=palette.grime,
                   base_rough=palette.roughness_hull)
    _paint_plating(albedo, rough, "accent", palette.accent, rng,
                   contrast=palette.panel_contrast * 0.6, grime=palette.grime * 0.7,
                   base_rough=max(palette.roughness_hull - 0.15, 0.15))
    _paint_plating(albedo, rough, "dark", palette.dark, rng,
                   contrast=palette.panel_contrast * 1.6, grime=palette.grime * 2.0,
                   base_rough=0.82)
    _paint_engine_glow(emission, albedo, "engine", palette.engine_glow, rng, size=size)
    _paint_windows(emission, albedo, "windows", palette.window_glow, palette.dark, rng, size=size)
    _paint_glow_strips(emission, albedo, "glow", palette.accent_glow, rng,
                       veins=True, size=size)
    x0, y0, x1, y1 = _region_px("metal", size)
    albedo[y0:y1, x0:x1, :3] = np.array(palette.metal, dtype=np.float32)
    noise = _value_noise((y1 - y0, x1 - x0), rng)
    albedo[y0:y1, x0:x1, :3] *= (0.9 + noise[..., None] * 0.2)
    metal[y0:y1, x0:x1] = 1.0
    rough[y0:y1, x0:x1] = palette.roughness_metal
    _paint_greeble(albedo, rough, metal, "greeble", palette.dark, palette.metal, rng, size=size)

    orm = np.zeros((size, size, 4), dtype=np.float32)
    orm[..., 0] = 1.0  # occlusion unused (baked into albedo)
    orm[..., 1] = rough
    orm[..., 2] = metal
    orm[..., 3] = 1.0
    return {"albedo": albedo, "emission": emission, "orm": orm}


def save_image(name, array, out_dir, srgb=True):
    h, w = array.shape[:2]
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    img.pixels.foreach_set(array.astype(np.float32).ravel())
    path = os.path.join(out_dir, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


# ---------------------------------------------------------------------------
# Material
# ---------------------------------------------------------------------------

def build_material(set_id, images, emission_strength=2.2):
    mat = bpy.data.materials.new(f"{set_id}_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_a = nt.nodes.new("ShaderNodeTexImage")
    tex_a.image = images["albedo"]
    nt.links.new(tex_a.outputs["Color"], bsdf.inputs["Base Color"])

    tex_e = nt.nodes.new("ShaderNodeTexImage")
    tex_e.image = images["emission"]
    nt.links.new(tex_e.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = emission_strength

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.image = images["orm"]
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


# ---------------------------------------------------------------------------
# Scene / export / preview
# ---------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def export_glb(objects, filepath):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_image_format="AUTO",
        export_normals=True,
        export_tangents=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
    )


def tri_count(obj):
    return sum(max(len(p.vertices) - 2, 0) for p in obj.data.polygons)


def render_previews(objects, out_dir, set_id, accent=(0.8, 0.85, 1.0)):
    """Render each object alone on dark background, then a contact sheet."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = False

    # Ambient-ish dark navy background gives gentle fill so large flat panels
    # do not blow out under the key light (closer to the in-game look, where
    # Godot uses ambient_light_energy ~0.9 plus a soft directional key).
    world = bpy.data.worlds.new("preview_world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.020, 0.028, 0.045, 1.0)
    bg.inputs[1].default_value = 1.6
    scene.world = world

    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(6.0)  # soft shadows
    sun.rotation_euler = (math.radians(55), math.radians(-12), math.radians(35))
    scene.collection.objects.link(sun)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 1.3
    fill.data.color = accent
    fill.data.angle = math.radians(10.0)
    fill.rotation_euler = (math.radians(-60), math.radians(30), math.radians(-140))
    scene.collection.objects.link(fill)
    rim = bpy.data.objects.new("rim", bpy.data.lights.new("rim", "SUN"))
    rim.data.energy = 1.1
    rim.data.color = (0.7, 0.8, 1.0)
    rim.rotation_euler = (math.radians(-24), math.radians(-40), math.radians(150))
    scene.collection.objects.link(rim)

    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    paths = []
    for obj in objects:
        for other in objects:
            other.hide_render = other is not obj
        # frame object from a 3/4 top view
        dims = obj.dimensions
        radius = max(dims.x, dims.y, dims.z) * 0.72 + 0.6
        direction = Vector((-1.0, 1.15, 0.78)).normalized()
        center = Vector(obj.bound_box[0]) + Vector(obj.bound_box[6])
        center = obj.matrix_world @ (center * 0.5)
        cam.location = center + direction * radius * 2.05
        look = center - cam.location
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(out_dir, f"{set_id}_{obj.name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    for other in objects:
        other.hide_render = False

    # contact sheet
    cols = 4
    rows = (len(paths) + cols - 1) // cols
    sheet = np.zeros((rows * 512, cols * 512, 4), dtype=np.float32)
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        arr = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
        r, c = i // cols, i % cols
        sheet[(rows - 1 - r) * 512:(rows - r) * 512, c * 512:(c + 1) * 512] = arr
        bpy.data.images.remove(img)
    sheet_img = bpy.data.images.new("sheet", width=cols * 512, height=rows * 512, alpha=True)
    sheet_img.pixels.foreach_set(sheet.ravel())
    sheet_path = os.path.join(out_dir, f"{set_id}_contact_sheet.png")
    sheet_img.filepath_raw = sheet_path
    sheet_img.file_format = "PNG"
    sheet_img.save()
    return sheet_path
