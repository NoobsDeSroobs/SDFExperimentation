// A simple human built from 9 rounded cylinders and a sphere.
// Local space: feet at y = 0, about 1.8 tall, facing +z.

const vec3  HUMAN_CENTER = vec3(0.0, 1, 0.0);
const float HUMAN_RADIUS = 5.5;

// How far the parts melt into each other; 0 would be hard edges
const float HUMAN_BLEND = 0.06;

// human_local_point: the point to measure from, relative to the human's feet
Surface sdHuman(vec3 human_local_point) {
    const float blend_distance = HUMAN_BLEND;
    // Each cylinder has the form (start point, end point, radius, edge rounding)
    float human_distance = sdSphere(human_local_point - vec3(0.0, 1.62, 0.0), 0.12);                                                  // head

    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(0.0, 1.0, 0.0),    vec3(0.0, 1.50, 0.0),    0.17,  0.12,  blend_distance);  // torso

    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(-0.16, 1.46, 0.0), vec3(-0.40, 1.14, 0.0),  0.05,  0.04,  blend_distance);  // left upper arm
    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(-0.40, 1.14, 0.0), vec3(-0.48, 0.84, 0.05), 0.04,  0.03,  blend_distance);  // left forearm
    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(0.16, 1.46, 0.0),  vec3(0.40, 1.14, 0.0),   0.05,  0.04,  blend_distance);  // right upper arm
    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(0.40, 1.14, 0.0),  vec3(0.48, 0.84, 0.05),  0.04,  0.03,  blend_distance);  // right forearm

    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(-0.10, 1.08, 0.0), vec3(-0.11, 0.52, 0.0),  0.07,  0.055, blend_distance);  // left thigh
    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(-0.11, 0.54, 0.0), vec3(-0.11, 0.02, 0.0),  0.055, 0.045, blend_distance);  // left shin
    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(0.10, 1.08, 0.0),  vec3(0.11, 0.52, 0.0),   0.07,  0.055, blend_distance);  // right thigh
    human_distance = smoothAddRoundCylinder(human_distance, human_local_point, vec3(0.11, 0.54, 0.0),  vec3(0.11, 0.02, 0.0),   0.055, 0.045, blend_distance);  // right shin

    return Surface(human_distance, COLOR_SKIN);
}
