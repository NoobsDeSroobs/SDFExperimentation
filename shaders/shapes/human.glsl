// A simple human built from 9 rounded cylinders and a sphere.
// Local space: feet at y = 0, about 1.8 tall, facing +z.

const vec3  HUMAN_CENTER = vec3(0.0, 1, 0.0);
const float HUMAN_RADIUS = 5.5;

// How far the parts melt into each other; 0 would be hard edges
const float HUMAN_BLEND = 0.06;

vec2 sdHuman(vec3 p) {
    const float k = HUMAN_BLEND;
    // Each cylinder has the form (from, to, radius, edge rounding)
    float d = sdSphere(p - vec3(0.0, 1.62, 0.0), 0.12);                                              // head

    d = smoothAddRoundCylinder(d, p, vec3(0.0, 1.0, 0.0),   vec3(0.0, 1.50, 0.0),    0.17,  0.12,  k);  // torso

    d = smoothAddRoundCylinder(d, p, vec3(-0.16, 1.46, 0.0), vec3(-0.40, 1.14, 0.0),  0.05,  0.04,  k);  // left upper arm
    d = smoothAddRoundCylinder(d, p, vec3(-0.40, 1.14, 0.0), vec3(-0.48, 0.84, 0.05), 0.04,  0.03,  k);  // left forearm
    d = smoothAddRoundCylinder(d, p, vec3(0.16, 1.46, 0.0),  vec3(0.40, 1.14, 0.0),   0.05,  0.04,  k);  // right upper arm
    d = smoothAddRoundCylinder(d, p, vec3(0.40, 1.14, 0.0),  vec3(0.48, 0.84, 0.05),  0.04,  0.03,  k);  // right forearm

    d = smoothAddRoundCylinder(d, p, vec3(-0.10, 1.08, 0.0), vec3(-0.11, 0.52, 0.0),  0.07,  0.055, k);  // left thigh
    d = smoothAddRoundCylinder(d, p, vec3(-0.11, 0.54, 0.0), vec3(-0.11, 0.02, 0.0),  0.055, 0.045, k);  // left shin
    d = smoothAddRoundCylinder(d, p, vec3(0.10, 1.08, 0.0),  vec3(0.11, 0.52, 0.0),   0.07,  0.055, k);  // right thigh
    d = smoothAddRoundCylinder(d, p, vec3(0.11, 0.54, 0.0),  vec3(0.11, 0.02, 0.0),   0.055, 0.045, k);  // right shin

    return vec2(d, MAT_SKIN);
}
