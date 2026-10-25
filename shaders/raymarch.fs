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

// Resolved by the Rust loader (GLSL has no #include)
#include "sdf.glsl"
#include "shapes/human.glsl"

// ---- Scene: map() returns vec2(distance, material id) ----
vec2 map(vec3 p) {
    vec2 res = vec2(sdPlane(p, -1.0), MAT_GROUND);

    // Two blobs smoothly merging
    vec3 c = vec3(sin(g_time) * 0.7, 0.0, 0.0);
    float blob = opSmoothUnion(sdSphere(p - c, 0.6), sdSphere(p + c, 0.6), 0.5);
    res = opUnion(res, vec2(blob, MAT_BLOB));

    // Rounded box
    res = opUnion(res, vec2(sdRoundBox(p - vec3(3.0, -0.5, 0.0), vec3(0.4), 0.1), MAT_BOX));

    // Spinning torus
    vec3 t = p - vec3(-3.0, 0.0, 0.0);
    float a = g_time * 0.8, ca = cos(a), sa = sin(a);
    t.yz = mat2(ca, sa, -sa, ca) * t.yz;
    res = opUnion(res, vec2(sdTorus(t, vec2(0.7, 0.22)), MAT_TORUS));

    // Grid of spheres further back, via domain repetition
    vec3 q = p - vec3(0.0, -0.4, 8.0);
    q.xz = mod(q.xz + 2.0, 4.0) - 2.0;
    res = opUnion(res, vec2(sdSphere(q, 0.6), MAT_SPHERE));

    // A human with its feet on the ground, skipped cheaply when the ray is far away
    vec3 h = p - vec3(0.0, -1.0, 3.0);
    BOUNDED(res, h, HUMAN_CENTER, HUMAN_RADIUS, sdHuman(h));

    return res;
}

vec3 calcNormal(vec3 p) {
    const vec2 e = vec2(1.0, -1.0) * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}

float softShadow(vec3 ro, vec3 rd, float tmax) {
    float res = 1.0, t = 0.02;
    for (int i = 0; i < 64; i++) {
        float h = map(ro + rd * t).x;
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.01, 0.5);
        if (res < 0.001 || t > tmax) break;
    }
    return clamp(res, 0.0, 1.0);
}

float calcAO(vec3 p, vec3 n) {
    float occ = 0.0, sca = 1.0;
    for (int i = 0; i < 5; i++) {
        float h = 0.01 + 0.12 * float(i) / 4.0;
        occ += (h - map(p + n * h).x) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

vec3 materialColor(float id, vec3 p) {
    if (id < 0.5) {
        float checker = mod(floor(p.x) + floor(p.z), 2.0);
        return mix(vec3(0.25), vec3(0.6), checker);
    }
    if (id < 1.5) return vec3(0.9, 0.35, 0.25);
    if (id < 2.5) return vec3(0.3, 0.7, 0.4);
    if (id < 3.5) return vec3(0.9, 0.8, 0.3);
    if (id > 4.5) return vec3(0.85, 0.65, 0.55);
    return vec3(0.4, 0.5, 0.9);
}

void main() {
    // Pixel -> [-aspect, aspect] x [-1, 1]
    vec2 uv = (2.0 * gl_FragCoord.xy - g_resolution) / g_resolution.y;
    vec3 rd = normalize(uv.x * g_camRight + uv.y * g_camUp + g_focalLength * g_camForward);

    // Sphere tracing
    float t = g_zNear;
    float id = -1.0;
    for (int i = 0; i < g_rmSteps; i++) {
        vec2 h = map(g_eye + rd * t);
        if (h.x < g_rmEpsilon) { id = h.y; break; }
        t += h.x;
        if (t > g_zFar) break;
    }

    vec3 sky = g_skyColor.rgb - 0.4 * rd.y;
    vec3 col = sky;

    if (id >= 0.0) {
        vec3 p = g_eye + rd * t;
        vec3 n = calcNormal(p);
        vec3 toLight = g_light0Position - p;
        float dist = length(toLight);
        vec3 l = toLight / dist;

        float diff = max(dot(n, l), 0.0) * softShadow(p + n * 0.01, l, dist);
        float spec = pow(max(dot(reflect(-l, n), -rd), 0.0), 32.0) * step(0.0, dot(n, l));
        float atten = 1.0 / (1.0 + 0.05 * dist * dist);
        float ao = calcAO(p, n);

        vec3 albedo = materialColor(id, p);
        col = albedo * g_ambient.rgb * ao
            + (albedo * diff + spec * 0.5) * g_light0Color.rgb * atten * 2.0;

        // Distance fog into the sky color
        col = mix(col, sky, 1.0 - exp(-0.0008 * t * t));
    }

    fragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
