// Exact angular extent of circular map emitters; no directional sampling.
// Projected blocker intervals provide soft penumbrae in the map plane.
uniform int body_count = 0;
uniform vec4 bodies[32];
uniform vec4 body_colors[32];

vec3 map_direct_light(vec2 p) {
	vec3 result = vec3(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= body_count) { break; }
		if (bodies[i].w <= 0.0) { continue; }
		vec2 delta = bodies[i].xy - p;
		float distance_to_light = length(delta);
		float radius = bodies[i].z;
		if (distance_to_light <= radius) {
			result += body_colors[i].rgb * bodies[i].w;
			continue;
		}
		float half_angle = asin(clamp(radius / distance_to_light, 0.0, 1.0));
		vec2 direction = delta / distance_to_light;
		float visibility = 1.0;
		for (int j = 0; j < 32; j++) {
			if (j >= body_count) { break; }
			if (i == j) { continue; }
			vec2 blocker = bodies[j].xy - p;
			float blocker_distance = length(blocker);
			if (blocker_distance - bodies[j].z >= distance_to_light - radius) { continue; }
			if (blocker_distance <= bodies[j].z) { visibility = 0.0; break; }
			float angle = atan(direction.x * blocker.y - direction.y * blocker.x, dot(direction, blocker));
			float blocker_angle = asin(clamp(bodies[j].z / blocker_distance, 0.0, 1.0));
			float overlap = max(0.0, min(half_angle, angle + blocker_angle) - max(-half_angle, angle - blocker_angle));
			visibility *= 1.0 - clamp(overlap / (2.0 * half_angle), 0.0, 1.0);
		}
		result += body_colors[i].rgb * bodies[i].w * (half_angle / 3.14159265359) * visibility;
	}
	return result;
}
