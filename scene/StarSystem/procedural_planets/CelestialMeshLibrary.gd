extends RefCounted
class_name CelestialMeshLibrary

## Shared, globally cached meshes for the 3D celestial body pipeline.
## All meshes are unit-sized (diameter/outer radius 1.0) and scaled per body
## via node scale, so a single instance serves every system ever opened.
## Rock variants use fixed constant seeds (1000 + variant) so the same six
## meshes are reused across all belts and runs; per-belt variety comes from
## instance transforms and tints, not geometry.

const ANNULUS_SEGMENTS := 128
const ROCK_VARIANT_COUNT := 6

static var _cache: Dictionary = {}


## Unit sphere (radius 0.5) shared by planet surfaces, cloud/atmosphere shells
## and star bodies. 96x48 keeps the silhouette smooth at closest zoom.
static func get_body_sphere() -> SphereMesh:
	if _cache.has("body_sphere"):
		return _cache["body_sphere"]
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 96
	sphere.rings = 48
	_cache["body_sphere"] = sphere
	return sphere


## Flat XZ annulus, inner radius 0.5 / outer radius 1.0, UV.x = angle / TAU,
## UV.y = radial 0 (inner) -> 1 (outer). Shared by planetary rings and the
## black hole accretion disk; per-body inner/outer fractions are shader-side.
static func get_annulus_mesh() -> ArrayMesh:
	if _cache.has("annulus"):
		return _cache["annulus"]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment_index in range(ANNULUS_SEGMENTS):
		var angle_0 := TAU * float(segment_index) / float(ANNULUS_SEGMENTS)
		var angle_1 := TAU * float(segment_index + 1) / float(ANNULUS_SEGMENTS)
		var u_0 := float(segment_index) / float(ANNULUS_SEGMENTS)
		var u_1 := float(segment_index + 1) / float(ANNULUS_SEGMENTS)
		var dir_0 := Vector3(cos(angle_0), 0.0, sin(angle_0))
		var dir_1 := Vector3(cos(angle_1), 0.0, sin(angle_1))
		var inner_0 := dir_0 * 0.5
		var inner_1 := dir_1 * 0.5
		var outer_0 := dir_0
		var outer_1 := dir_1
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(u_0, 0.0))
		surface.add_vertex(inner_0)
		surface.set_uv(Vector2(u_0, 1.0))
		surface.add_vertex(outer_0)
		surface.set_uv(Vector2(u_1, 1.0))
		surface.add_vertex(outer_1)
		surface.set_uv(Vector2(u_0, 0.0))
		surface.add_vertex(inner_0)
		surface.set_uv(Vector2(u_1, 1.0))
		surface.add_vertex(outer_1)
		surface.set_uv(Vector2(u_1, 0.0))
		surface.add_vertex(inner_1)
	var mesh := surface.commit()
	_cache["annulus"] = mesh
	return mesh


## Lumpy low-poly rock (icosphere subdiv 1, 42 verts), max extent ~1.0.
## Vertex COLOR.r carries normalized displacement (0 = crevice, 1 = peak)
## as a cheap AO channel for AsteroidRock.gdshader. Facet normals come from
## screen-space derivatives in the shader, so smooth normals here are fine.
static func get_rock_mesh(variant_index: int) -> ArrayMesh:
	var cache_key := "rock_%d" % (variant_index % ROCK_VARIANT_COUNT)
	if _cache.has(cache_key):
		return _cache[cache_key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + (variant_index % ROCK_VARIANT_COUNT)
	var icosphere := _build_icosphere(1)
	var base_vertices: PackedVector3Array = icosphere["vertices"]
	var indices: PackedInt32Array = icosphere["indices"]
	var squash := Vector3(1.0, rng.randf_range(0.68, 1.0), rng.randf_range(0.8, 1.2))
	var displacements := PackedFloat32Array()
	var min_displacement := 10.0
	var max_displacement := -10.0
	for vertex in base_vertices:
		var displacement := rng.randf_range(0.7, 1.3)
		displacements.append(displacement)
		min_displacement = minf(min_displacement, displacement)
		max_displacement = maxf(max_displacement, displacement)
	var displacement_span := maxf(max_displacement - min_displacement, 0.0001)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for vertex_index in range(base_vertices.size()):
		var direction := base_vertices[vertex_index]
		var displaced := direction * displacements[vertex_index] * 0.5
		vertices.append(displaced * squash)
		normals.append(direction)
		var ao := (displacements[vertex_index] - min_displacement) / displacement_span
		colors.append(Color(ao, ao, ao, 1.0))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[cache_key] = mesh
	return mesh


## Half-torus arc tube for 3D star prominences: a semicircular arc of radius
## 0.5 in the local XY plane (feet at x = +/-0.5, apex at y = +0.5), tube
## radius 0.07. UV.x runs along the arc (0 = foot, 0.5 = apex, 1 = foot),
## UV.y around the tube. Scaled and oriented per arm by ProceduralStarVisual.
static func get_prominence_arc() -> ArrayMesh:
	if _cache.has("prominence_arc"):
		return _cache["prominence_arc"]
	const ARC_SEGMENTS := 24
	const TUBE_SEGMENTS := 8
	const TUBE_RADIUS := 0.04
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for arc_index in range(ARC_SEGMENTS + 1):
		var arc_t := float(arc_index) / float(ARC_SEGMENTS)
		var arc_angle := PI * arc_t
		var ring_center := Vector3(cos(arc_angle), sin(arc_angle), 0.0) * 0.5
		var radial := Vector3(cos(arc_angle), sin(arc_angle), 0.0)
		var binormal := Vector3(0.0, 0.0, 1.0)
		# Taper toward the apex so arcs read as flames, not sausages.
		var ring_radius := TUBE_RADIUS * (1.0 - 0.5 * sin(arc_t * PI))
		for tube_index in range(TUBE_SEGMENTS + 1):
			var tube_t := float(tube_index) / float(TUBE_SEGMENTS)
			var tube_angle := TAU * tube_t
			var offset := (radial * cos(tube_angle) + binormal * sin(tube_angle)) * ring_radius
			surface.set_normal(offset.normalized())
			surface.set_uv(Vector2(arc_t, tube_t))
			surface.add_vertex(ring_center + offset)
	# Stitch quads between consecutive rings.
	var ring_stride := TUBE_SEGMENTS + 1
	for arc_index in range(ARC_SEGMENTS):
		for tube_index in range(TUBE_SEGMENTS):
			var a := arc_index * ring_stride + tube_index
			var b := a + 1
			var c := a + ring_stride
			var d := c + 1
			surface.add_index(a)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(d)
	var mesh := surface.commit()
	_cache["prominence_arc"] = mesh
	return mesh


## Open cone (apex up at +0.5, base radius 0.5 at -0.5) for neutron star
## beams; rendered additively, no caps.
static func get_beam_cone() -> CylinderMesh:
	if _cache.has("beam_cone"):
		return _cache["beam_cone"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 4
	cone.cap_top = false
	cone.cap_bottom = false
	_cache["beam_cone"] = cone
	return cone


# Construction uses a plain Array (reference type) because packed arrays are
# copy-on-write value types and would not survive mutation in _get_midpoint().
static func _build_icosphere(subdivisions: int) -> Dictionary:
	var golden := (1.0 + sqrt(5.0)) / 2.0
	var vertices: Array = [
		Vector3(-1.0, golden, 0.0), Vector3(1.0, golden, 0.0),
		Vector3(-1.0, -golden, 0.0), Vector3(1.0, -golden, 0.0),
		Vector3(0.0, -1.0, golden), Vector3(0.0, 1.0, golden),
		Vector3(0.0, -1.0, -golden), Vector3(0.0, 1.0, -golden),
		Vector3(golden, 0.0, -1.0), Vector3(golden, 0.0, 1.0),
		Vector3(-golden, 0.0, -1.0), Vector3(-golden, 0.0, 1.0),
	]
	for vertex_index in range(vertices.size()):
		vertices[vertex_index] = (vertices[vertex_index] as Vector3).normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	for _subdivision in range(subdivisions):
		var midpoint_cache: Dictionary = {}
		var new_faces := []
		for face in faces:
			var mid_ab := _get_midpoint(vertices, midpoint_cache, face[0], face[1])
			var mid_bc := _get_midpoint(vertices, midpoint_cache, face[1], face[2])
			var mid_ca := _get_midpoint(vertices, midpoint_cache, face[2], face[0])
			new_faces.append([face[0], mid_ab, mid_ca])
			new_faces.append([face[1], mid_bc, mid_ab])
			new_faces.append([face[2], mid_ca, mid_bc])
			new_faces.append([mid_ab, mid_bc, mid_ca])
		faces = new_faces

	var packed_vertices := PackedVector3Array()
	for vertex in vertices:
		packed_vertices.append(vertex)
	var indices := PackedInt32Array()
	for face in faces:
		indices.append(face[0])
		indices.append(face[1])
		indices.append(face[2])
	return {"vertices": packed_vertices, "indices": indices}


static func _get_midpoint(vertices: Array, midpoint_cache: Dictionary, index_a: int, index_b: int) -> int:
	var cache_key := Vector2i(mini(index_a, index_b), maxi(index_a, index_b))
	if midpoint_cache.has(cache_key):
		return midpoint_cache[cache_key]
	var midpoint := ((vertices[index_a] as Vector3 + vertices[index_b] as Vector3) * 0.5).normalized()
	vertices.append(midpoint)
	var midpoint_index := vertices.size() - 1
	midpoint_cache[cache_key] = midpoint_index
	return midpoint_index
