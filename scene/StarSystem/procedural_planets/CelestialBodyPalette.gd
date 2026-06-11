extends RefCounted
class_name CelestialBodyPalette

## Seeded IQ cosine palettes for the 3D celestial body pipeline.
## Port of the vendored Planets/Planet.gd::_generate_new_colorscheme() with an
## explicit RandomNumberGenerator (no global RNG pollution) plus pastel clamps.
##
## A palette is a pure-data Dictionary {a, b, c, d: Vector3} evaluated as
## color(t) = a + b * cos(TAU * (c * t + d)) — both CPU-side (tests, belt
## tints, star ramps) and in shaders (celestial_common.gdshaderinc).


# Draw order: c.x, c.y, c.z, d.x, d.y, d.z, d_scale — append new draws only.
static func generate_palette(
	rng: RandomNumberGenerator,
	hue_diff: float = 0.9,
	saturation: float = 0.5
) -> Dictionary:
	var a := Vector3(0.5, 0.5, 0.5)
	var b := Vector3(0.5, 0.5, 0.5) * saturation
	var c := Vector3(
		rng.randf_range(0.5, 1.5),
		rng.randf_range(0.5, 1.5),
		rng.randf_range(0.5, 1.5)
	) * hue_diff
	var d := Vector3(
		rng.randf_range(0.0, 1.0),
		rng.randf_range(0.0, 1.0),
		rng.randf_range(0.0, 1.0)
	) * rng.randf_range(1.0, 3.0)
	return {"a": a, "b": b, "c": c, "d": d}


## Pulls the palette midline toward an anchor color (the orbital/star accent
## color from GalaxyGenerator) so the 3D body matches its UI/galaxy-map tint.
static func anchor_palette(palette: Dictionary, anchor: Color, strength: float = 0.45) -> Dictionary:
	var anchor_vec := Vector3(anchor.r, anchor.g, anchor.b)
	var a: Vector3 = palette.get("a", Vector3(0.5, 0.5, 0.5))
	var b: Vector3 = palette.get("b", Vector3(0.25, 0.25, 0.25))
	return {
		"a": a.lerp(anchor_vec, clampf(strength, 0.0, 1.0)),
		"b": b * (1.0 - clampf(strength, 0.0, 1.0) * 0.4),
		"c": palette.get("c", Vector3.ONE),
		"d": palette.get("d", Vector3.ZERO),
	}


static func evaluate(palette: Dictionary, t: float) -> Color:
	var a: Vector3 = palette.get("a", Vector3(0.5, 0.5, 0.5))
	var b: Vector3 = palette.get("b", Vector3(0.25, 0.25, 0.25))
	var c: Vector3 = palette.get("c", Vector3.ONE)
	var d: Vector3 = palette.get("d", Vector3.ZERO)
	return Color(
		clampf(a.x + b.x * cos(TAU * (c.x * t + d.x)), 0.0, 1.0),
		clampf(a.y + b.y * cos(TAU * (c.y * t + d.y)), 0.0, 1.0),
		clampf(a.z + b.z * cos(TAU * (c.z * t + d.z)), 0.0, 1.0)
	)


static func sample(palette: Dictionary, n_colors: int) -> PackedColorArray:
	var colors := PackedColorArray()
	var n := float(maxi(n_colors - 1, 1))
	for i in range(n_colors):
		colors.append(evaluate(palette, float(i) / n))
	return colors


## Clamps a color into a pastel HSV window: saturation capped, value floored
## and capped. The shader-side backstop lives in celestial_common.gdshaderinc;
## this CPU twin is used for discrete colors (belt tints, star ramps, tests).
static func pastelize(color: Color, sat_max: float, val_min: float, val_max: float) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(color.s, 0.0, sat_max),
		clampf(color.v, val_min, val_max),
		color.a
	)
