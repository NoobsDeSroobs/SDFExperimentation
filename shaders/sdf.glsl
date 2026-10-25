// Signed distance primitives and operations.
// Every sd* function returns the distance from a point to the shape (negative inside).
// Shape files in shapes/ are built from these.
//
// Naming of points, by the space they are expressed in:
//   world_point  - a position in the scene
//   local_point  - a position relative to the shape's own origin (what sd* functions take)

// What the scene returns for a point: how far the nearest surface is, and its colour.
// Smooth unions blend the colours as well as the distances.
struct Surface {
    float signed_distance;
    vec3  albedo_color;
};

const vec3 COLOR_BLOB   = vec3(0.9, 0.35, 0.25);
const vec3 COLOR_BOX    = vec3(0.3, 0.7, 0.4);
const vec3 COLOR_TORUS  = vec3(0.9, 0.8, 0.3);
const vec3 COLOR_SPHERE = vec3(0.4, 0.5, 0.9);
const vec3 COLOR_SKIN   = vec3(0.85, 0.65, 0.55);
const vec3 COLOR_BALL   = vec3(1.0, 0.05, 0.05);

// ---- Primitives (centred on the origin of local space) ----
float sdSphere(vec3 local_point, float radius) { return length(local_point) - radius; }

float sdBox(vec3 local_point, vec3 half_size) {
    vec3 distance_beyond_faces = abs(local_point) - half_size;
    return length(max(distance_beyond_faces, 0.0))
         + min(max(distance_beyond_faces.x, max(distance_beyond_faces.y, distance_beyond_faces.z)), 0.0);
}

float sdRoundBox(vec3 local_point, vec3 half_size, float edge_rounding) {
    return sdBox(local_point, half_size) - edge_rounding;
}

// ring_radius: distance from the centre to the middle of the tube, tube_radius: tube thickness
float sdTorus(vec3 local_point, float ring_radius, float tube_radius) {
    vec2 offset_from_ring = vec2(length(local_point.xz) - ring_radius, local_point.y);
    return length(offset_from_ring) - tube_radius;
}

float sdPlane(vec3 world_point, float plane_height) { return world_point.y - plane_height; }

// Cylinder along the y axis
float sdCylinder(vec3 local_point, float radius, float half_height) {
    vec2 distance_beyond_sides = abs(vec2(length(local_point.xz), local_point.y))
                               - vec2(radius, half_height);
    return min(max(distance_beyond_sides.x, distance_beyond_sides.y), 0.0)
         + length(max(distance_beyond_sides, 0.0));
}

// Cylinder with flat ends running from start_point to end_point
float sdCylinderBetween(vec3 local_point, vec3 start_point, vec3 end_point, float radius) {
    vec3 axis = end_point - start_point;
    vec3 start_to_point = local_point - start_point;
    float axis_length_squared = dot(axis, axis);
    float along_axis_scaled = dot(start_to_point, axis);

    float radial_excess = length(start_to_point * axis_length_squared - axis * along_axis_scaled)
                        - radius * axis_length_squared;
    float axial_excess = abs(along_axis_scaled - axis_length_squared * 0.5)
                       - axis_length_squared * 0.5;
    float radial_squared = radial_excess * radial_excess;
    float axial_squared = axial_excess * axial_excess * axis_length_squared;

    float signed_squared_distance = (max(radial_excess, axial_excess) < 0.0)
        ? -min(radial_squared, axial_squared)
        : (((radial_excess > 0.0) ? radial_squared : 0.0) + ((axial_excess > 0.0) ? axial_squared : 0.0));
    return sign(signed_squared_distance) * sqrt(abs(signed_squared_distance)) / axis_length_squared;
}

// Same cylinder with its edges rounded off by edge_rounding
// (0 <= edge_rounding < radius, and 2 * edge_rounding < length).
// edge_rounding = radius would give a capsule. The shape is shrunk by edge_rounding and then
// inflated by it again, so the overall size stays the same.
float sdRoundCylinderBetween(vec3 local_point, vec3 start_point, vec3 end_point, float radius, float edge_rounding) {
    vec3 axis_direction = normalize(end_point - start_point);
    return sdCylinderBetween(local_point, start_point + axis_direction * edge_rounding,
                             end_point - axis_direction * edge_rounding, radius - edge_rounding)
         - edge_rounding;
}

float sdCapsule(vec3 local_point, vec3 start_point, vec3 end_point, float radius) {
    vec3 start_to_point = local_point - start_point;
    vec3 axis = end_point - start_point;
    float fraction_along_axis = clamp(dot(start_to_point, axis) / dot(axis, axis), 0.0, 1.0);
    return length(start_to_point - axis * fraction_along_axis) - radius;
}

// ---- Combining distances ----
float opUnion(float distance_a, float distance_b)     { return min(distance_a, distance_b); }
float opSubtract(float distance_a, float distance_b)  { return max(distance_a, -distance_b); }   // A with B carved out
float opIntersect(float distance_a, float distance_b) { return max(distance_a, distance_b); }

float opSmoothUnion(float distance_a, float distance_b, float blend_distance) {
    float blend_factor = clamp(0.5 + 0.5 * (distance_b - distance_a) / blend_distance, 0.0, 1.0);
    return mix(distance_b, distance_a, blend_factor)
         - blend_distance * blend_factor * (1.0 - blend_factor);
}

float opSmoothSubtract(float distance_a, float distance_b, float blend_distance) {
    float blend_factor = clamp(0.5 - 0.5 * (distance_a + distance_b) / blend_distance, 0.0, 1.0);
    return mix(distance_a, -distance_b, blend_factor)
         + blend_distance * blend_factor * (1.0 - blend_factor);
}

float opSmoothIntersect(float distance_a, float distance_b, float blend_distance) {
    float blend_factor = clamp(0.5 - 0.5 * (distance_b - distance_a) / blend_distance, 0.0, 1.0);
    return mix(distance_b, distance_a, blend_factor)
         + blend_distance * blend_factor * (1.0 - blend_factor);
}

// The same operations on surfaces. Hard union keeps the nearer surface (and its colour).
Surface opUnion(Surface surface_a, Surface surface_b) {
    return surface_a.signed_distance < surface_b.signed_distance ? surface_a : surface_b;
}

// Smooth union that also mixes the colours, using the same blend factor as the distances
Surface opSmoothUnion(Surface surface_a, Surface surface_b, float blend_distance) {
    float blend_factor = clamp(0.5 + 0.5 * (surface_b.signed_distance - surface_a.signed_distance)
                               / blend_distance, 0.0, 1.0);
    float blended_distance = mix(surface_b.signed_distance, surface_a.signed_distance, blend_factor)
                           - blend_distance * blend_factor * (1.0 - blend_factor);
    vec3 blended_color = mix(surface_b.albedo_color, surface_a.albedo_color, blend_factor);
    return Surface(blended_distance, blended_color);
}

// ---- Building shapes: add/subtract a primitive to the distance so far ----
// distance_so_far: the shape's distance accumulated so far
// sample_point: the point being measured from, in the same space as shape_origin_point
// shape_origin_point: where the primitive sits
float addSphere(float distance_so_far, vec3 sample_point, vec3 shape_origin_point, float radius) {
    return opUnion(distance_so_far, sdSphere(sample_point - shape_origin_point, radius));
}
float subtractSphere(float distance_so_far, vec3 sample_point, vec3 shape_origin_point, float radius) {
    return opSubtract(distance_so_far, sdSphere(sample_point - shape_origin_point, radius));
}
float smoothAddSphere(float distance_so_far, vec3 sample_point, vec3 shape_origin_point, float radius, float blend_distance) {
    return opSmoothUnion(distance_so_far, sdSphere(sample_point - shape_origin_point, radius), blend_distance);
}

float addBox(float distance_so_far, vec3 sample_point, vec3 shape_origin_point, vec3 half_size) {
    return opUnion(distance_so_far, sdBox(sample_point - shape_origin_point, half_size));
}
float subtractBox(float distance_so_far, vec3 sample_point, vec3 shape_origin_point, vec3 half_size) {
    return opSubtract(distance_so_far, sdBox(sample_point - shape_origin_point, half_size));
}
float smoothAddBox(float distance_so_far, vec3 sample_point, vec3 shape_origin_point, vec3 half_size, float blend_distance) {
    return opSmoothUnion(distance_so_far, sdBox(sample_point - shape_origin_point, half_size), blend_distance);
}

float addCylinder(float distance_so_far, vec3 sample_point, vec3 start_point, vec3 end_point, float radius) {
    return opUnion(distance_so_far, sdCylinderBetween(sample_point, start_point, end_point, radius));
}
float subtractCylinder(float distance_so_far, vec3 sample_point, vec3 start_point, vec3 end_point, float radius) {
    return opSubtract(distance_so_far, sdCylinderBetween(sample_point, start_point, end_point, radius));
}
float smoothAddCylinder(float distance_so_far, vec3 sample_point, vec3 start_point, vec3 end_point, float radius, float blend_distance) {
    return opSmoothUnion(distance_so_far, sdCylinderBetween(sample_point, start_point, end_point, radius), blend_distance);
}

float addRoundCylinder(float distance_so_far, vec3 sample_point, vec3 start_point, vec3 end_point, float radius, float edge_rounding) {
    return opUnion(distance_so_far, sdRoundCylinderBetween(sample_point, start_point, end_point, radius, edge_rounding));
}
float subtractRoundCylinder(float distance_so_far, vec3 sample_point, vec3 start_point, vec3 end_point, float radius, float edge_rounding) {
    return opSubtract(distance_so_far, sdRoundCylinderBetween(sample_point, start_point, end_point, radius, edge_rounding));
}
float smoothAddRoundCylinder(float distance_so_far, vec3 sample_point, vec3 start_point, vec3 end_point, float radius, float edge_rounding, float blend_distance) {
    return opSmoothUnion(distance_so_far, sdRoundCylinderBetween(sample_point, start_point, end_point, radius, edge_rounding), blend_distance);
}

// ---- Bounding spheres ----
// Every shape declares a sphere (in its own local space) that contains it. A point
// farther than BOUND_MARGIN outside that sphere returns the cheap sphere distance, which
// never exceeds the true distance, so marching stays safe. Only near the sphere is the
// full shape evaluated. Use inside map():
//   vec3 human_local_point = world_point - human_world_position;
//   BOUNDED(nearest_surface, human_local_point, HUMAN_CENTER, HUMAN_RADIUS, sdHuman(human_local_point));
#define BOUND_MARGIN 0.2
#define BOUNDED(nearest_surface, local_point, bound_center_point, bound_radius, shape_call) { \
    float distance_to_bound = length((local_point) - (bound_center_point)) - (bound_radius); \
    if (distance_to_bound > BOUND_MARGIN) nearest_surface = opUnion(nearest_surface, Surface(distance_to_bound, vec3(0.0))); \
    else nearest_surface = opUnion(nearest_surface, shape_call); \
}
