#version 330 core
out vec4 fragColor;

uniform vec2  g_resolution;
uniform vec3  g_camUp;
uniform vec3  g_camRight;
uniform vec3  g_camForward;
uniform vec3  g_eye;
uniform float g_focalLength;
uniform float g_zNear;
uniform float g_zFar;
uniform int   g_rmSteps;
uniform float g_rmEpsilon;
uniform vec4  g_skyColor;
uniform vec4  g_ambient;
uniform vec3  g_light0Position;
uniform vec4  g_light0Color;
uniform float g_time;
#define MAX_BALLS 8
uniform vec4  g_balls[MAX_BALLS];

// Resolved by the Rust loader (GLSL has no #include)
#include "sdf.glsl"
#include "shapes/human.glsl"
#include "shapes/bouncing_ball.glsl"

// ---- Scene ----
// Returns vec2(distance, material id) of the surface nearest to world_point.
vec2 map(vec3 world_point) {
    vec2 nearest_surface = vec2(sdPlane(world_point, -1.0), MAT_GROUND);

    // Two blobs smoothly merging
    vec3 blob_offset = vec3(sin(g_time) * 0.7, 0.0, 0.0);
    float blob_distance = opSmoothUnion(sdSphere(world_point - blob_offset, 0.6),
                                        sdSphere(world_point + blob_offset, 0.6), 0.5);
    nearest_surface = opUnion(nearest_surface, vec2(blob_distance, MAT_BLOB));

    // Rounded box
    vec3 box_local_point = world_point - vec3(3.0, -0.5, 0.0);
    nearest_surface = opUnion(nearest_surface,
                              vec2(sdRoundBox(box_local_point, vec3(0.4), 0.1), MAT_BOX));

    // Spinning torus
    vec3 torus_local_point = world_point - vec3(-3.0, 0.0, 0.0);
    float torus_angle = g_time * 0.8;
    float torus_cos = cos(torus_angle);
    float torus_sin = sin(torus_angle);
    torus_local_point.yz = mat2(torus_cos, torus_sin, -torus_sin, torus_cos) * torus_local_point.yz;
    nearest_surface = opUnion(nearest_surface,
                              vec2(sdTorus(torus_local_point, 0.7, 0.22), MAT_TORUS));

    // Grid of spheres further back, via domain repetition
    vec3 grid_local_point = world_point - vec3(0.0, -0.4, 8.0);
    grid_local_point.xz = mod(grid_local_point.xz + 2.0, 4.0) - 2.0;
    nearest_surface = opUnion(nearest_surface, vec2(sdSphere(grid_local_point, 0.6), MAT_SPHERE));

    // A human with its feet on the ground, skipped cheaply when the ray is far away
    vec3 human_local_point = world_point - vec3(0.0, -4.0, 12.0);
    BOUNDED(nearest_surface, human_local_point, HUMAN_CENTER, HUMAN_RADIUS, sdHuman(human_local_point));

    // Must come last: the balls blend into everything above
    nearest_surface = addBalls(nearest_surface, world_point);

    return nearest_surface;
}

// Direction the surface faces at world_point, from the gradient of the distance field
vec3 calcNormal(vec3 world_point) {
    const vec2 offset_signs = vec2(1.0, -1.0) * 0.0005;
    return normalize(offset_signs.xyy * map(world_point + offset_signs.xyy).x +
                     offset_signs.yyx * map(world_point + offset_signs.yyx).x +
                     offset_signs.yxy * map(world_point + offset_signs.yxy).x +
                     offset_signs.xxx * map(world_point + offset_signs.xxx).x);
}

// 1 = fully lit, 0 = fully in shadow, along a ray from shadow_ray_origin_point
float softShadow(vec3 shadow_ray_origin_point, vec3 shadow_ray_direction, float max_distance) {
    float shadow_amount = 1.0;
    float travelled_distance = 0.02;
    for (int march_step = 0; march_step < 64; march_step++) {
        float nearest_distance = map(shadow_ray_origin_point + shadow_ray_direction * travelled_distance).x;
        shadow_amount = min(shadow_amount, 8.0 * nearest_distance / travelled_distance);
        travelled_distance += clamp(nearest_distance, 0.01, 0.5);
        if (shadow_amount < 0.001 || travelled_distance > max_distance) break;
    }
    return clamp(shadow_amount, 0.0, 1.0);
}

float calcAmbientOcclusion(vec3 surface_world_point, vec3 surface_normal) {
    float occlusion = 0.0;
    float falloff = 1.0;
    for (int sample_index = 0; sample_index < 5; sample_index++) {
        float sample_height = 0.01 + 0.12 * float(sample_index) / 4.0;
        float nearest_distance = map(surface_world_point + surface_normal * sample_height).x;
        occlusion += (sample_height - nearest_distance) * falloff;
        falloff *= 0.95;
    }
    return clamp(1.0 - 3.0 * occlusion, 0.0, 1.0);
}

vec3 materialColor(float material_id, vec3 surface_world_point) {
    if (material_id < 0.5) {
        float checker = mod(floor(surface_world_point.x) + floor(surface_world_point.z), 2.0);
        return mix(vec3(0.25), vec3(0.6), checker);
    }
    if (material_id < 1.5) return vec3(0.9, 0.35, 0.25);
    if (material_id < 2.5) return vec3(0.3, 0.7, 0.4);
    if (material_id < 3.5) return vec3(0.9, 0.8, 0.3);
    if (material_id > 5.5) return vec3(1.0, 0.05, 0.05);
    if (material_id > 4.5) return vec3(0.85, 0.65, 0.55);
    return vec3(0.4, 0.5, 0.9);
}

void main() {
    // Pixel -> [-aspect, aspect] x [-1, 1]
    vec2 screen_position = (2.0 * gl_FragCoord.xy - g_resolution) / g_resolution.y;
    vec3 ray_origin_point = g_eye;
    vec3 ray_direction = normalize(screen_position.x * g_camRight + screen_position.y * g_camUp
                                   + g_focalLength * g_camForward);

    // Sphere tracing
    float travelled_distance = g_zNear;
    float hit_material_id = -1.0;
    for (int march_step = 0; march_step < g_rmSteps; march_step++) {
        vec2 nearest_surface = map(ray_origin_point + ray_direction * travelled_distance);
        if (nearest_surface.x < g_rmEpsilon) { hit_material_id = nearest_surface.y; break; }
        travelled_distance += nearest_surface.x;
        if (travelled_distance > g_zFar) break;
    }

    vec3 sky_color = g_skyColor.rgb - 0.4 * ray_direction.y;
    vec3 pixel_color = sky_color;

    if (hit_material_id >= 0.0) {
        vec3 hit_world_point = ray_origin_point + ray_direction * travelled_distance;
        vec3 surface_normal = calcNormal(hit_world_point);
        vec3 hit_to_light = g_light0Position - hit_world_point;
        float light_distance = length(hit_to_light);
        vec3 light_direction = hit_to_light / light_distance;

        float diffuse = max(dot(surface_normal, light_direction), 0.0)
                      * softShadow(hit_world_point + surface_normal * 0.01, light_direction, light_distance);
        float specular = pow(max(dot(reflect(-light_direction, surface_normal), -ray_direction), 0.0), 32.0)
                       * step(0.0, dot(surface_normal, light_direction));
        float light_attenuation = 1.0 / (1.0 + 0.05 * light_distance * light_distance);
        float ambient_occlusion = calcAmbientOcclusion(hit_world_point, surface_normal);

        vec3 albedo = materialColor(hit_material_id, hit_world_point);
        pixel_color = albedo * g_ambient.rgb * ambient_occlusion
                    + (albedo * diffuse + specular * 0.5) * g_light0Color.rgb * light_attenuation * 2.0;

        // Distance fog into the sky color
        pixel_color = mix(pixel_color, sky_color,
                          1.0 - exp(-0.0008 * travelled_distance * travelled_distance));
    }

    fragColor = vec4(pow(clamp(pixel_color, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
