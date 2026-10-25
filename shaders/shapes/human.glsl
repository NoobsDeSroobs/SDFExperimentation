// A simple human built from 9 cylinders and a sphere.
// Local space: feet at y = 0, about 1.8 tall, facing +z.

const vec3  HUMAN_CENTER = vec3(0.0, 0.9, 0.0);
const float HUMAN_RADIUS = 1.1;

vec2 sdHuman(vec3 p) {
    float d = 1e5;

    d = addSphere(d, p, vec3(0.0, 1.66, 0.0), 0.12);                                // head

    d = addCylinder(d, p, vec3(0.0, 1.00, 0.0),    vec3(0.0, 1.50, 0.0),    0.17);  // torso

    d = addCylinder(d, p, vec3(-0.22, 1.46, 0.0),  vec3(-0.40, 1.14, 0.0),  0.05);  // left upper arm
    d = addCylinder(d, p, vec3(-0.40, 1.14, 0.0),  vec3(-0.48, 0.84, 0.05), 0.04);  // left forearm
    d = addCylinder(d, p, vec3(0.22, 1.46, 0.0),   vec3(0.40, 1.14, 0.0),   0.05);  // right upper arm
    d = addCylinder(d, p, vec3(0.40, 1.14, 0.0),   vec3(0.48, 0.84, 0.05),  0.04);  // right forearm

    d = addCylinder(d, p, vec3(-0.10, 1.00, 0.0),  vec3(-0.11, 0.52, 0.0),  0.07);  // left thigh
    d = addCylinder(d, p, vec3(-0.11, 0.52, 0.0),  vec3(-0.11, 0.02, 0.0),  0.055); // left shin
    d = addCylinder(d, p, vec3(0.10, 1.00, 0.0),   vec3(0.11, 0.52, 0.0),   0.07);  // right thigh
    d = addCylinder(d, p, vec3(0.11, 0.52, 0.0),   vec3(0.11, 0.02, 0.0),   0.055); // right shin

    return vec2(d, MAT_SKIN);
}
