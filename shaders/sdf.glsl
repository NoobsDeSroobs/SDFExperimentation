// Signed distance primitives and operations.
// Every sd* function returns the distance from p to the shape (negative inside).
// Shape files in shapes/ are built from these.

#define MAT_GROUND 0.0
#define MAT_BLOB   1.0
#define MAT_BOX    2.0
#define MAT_TORUS  3.0
#define MAT_SPHERE 4.0
#define MAT_SKIN   5.0

// ---- Primitives (centred on the origin) ----
float sdSphere(vec3 p, float r) { return length(p) - r; }

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdRoundBox(vec3 p, vec3 b, float r) { return sdBox(p, b) - r; }

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdPlane(vec3 p, float h) { return p.y - h; }

// Cylinder along the y axis: radius r, half-height h
float sdCylinder(vec3 p, float r, float h) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// Cylinder with flat ends running from point a to point b
float sdCylinderBetween(vec3 p, vec3 a, vec3 b, float r) {
    vec3 ba = b - a, pa = p - a;
    float baba = dot(ba, ba), paba = dot(pa, ba);
    float x = length(pa * baba - ba * paba) - r * baba;
    float y = abs(paba - baba * 0.5) - baba * 0.5;
    float x2 = x * x, y2 = y * y * baba;
    float d = (max(x, y) < 0.0) ? -min(x2, y2)
                                : (((x > 0.0) ? x2 : 0.0) + ((y > 0.0) ? y2 : 0.0));
    return sign(d) * sqrt(abs(d)) / baba;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ---- Combining distances ----
float opUnion(float a, float b)     { return min(a, b); }
float opSubtract(float a, float b)  { return max(a, -b); }   // a with b carved out
float opIntersect(float a, float b) { return max(a, b); }

float opSmoothUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float opSmoothSubtract(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (a + b) / k, 0.0, 1.0);
    return mix(a, -b, h) + k * h * (1.0 - h);
}

float opSmoothIntersect(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

// Same union for (distance, material id) pairs: keeps the nearer one
vec2 opUnion(vec2 a, vec2 b) { return a.x < b.x ? a : b; }

// ---- Building shapes: add/subtract a primitive to the distance d so far ----
// d: distance accumulated so far, p: the point, origin: where the primitive sits
float addSphere(float d, vec3 p, vec3 origin, float r) {
    return opUnion(d, sdSphere(p - origin, r));
}
float subtractSphere(float d, vec3 p, vec3 origin, float r) {
    return opSubtract(d, sdSphere(p - origin, r));
}
float smoothAddSphere(float d, vec3 p, vec3 origin, float r, float k) {
    return opSmoothUnion(d, sdSphere(p - origin, r), k);
}

float addBox(float d, vec3 p, vec3 origin, vec3 halfSize) {
    return opUnion(d, sdBox(p - origin, halfSize));
}
float subtractBox(float d, vec3 p, vec3 origin, vec3 halfSize) {
    return opSubtract(d, sdBox(p - origin, halfSize));
}
float smoothAddBox(float d, vec3 p, vec3 origin, vec3 halfSize, float k) {
    return opSmoothUnion(d, sdBox(p - origin, halfSize), k);
}

float addCylinder(float d, vec3 p, vec3 a, vec3 b, float r) {
    return opUnion(d, sdCylinderBetween(p, a, b, r));
}
float subtractCylinder(float d, vec3 p, vec3 a, vec3 b, float r) {
    return opSubtract(d, sdCylinderBetween(p, a, b, r));
}
float smoothAddCylinder(float d, vec3 p, vec3 a, vec3 b, float r, float k) {
    return opSmoothUnion(d, sdCylinderBetween(p, a, b, r), k);
}

// ---- Bounding spheres ----
// Every shape declares a sphere (in its own local space) that contains it. A point
// farther than BOUND_MARGIN outside that sphere returns the cheap sphere distance, which
// never exceeds the true distance, so marching stays safe. Only near the sphere is the
// full shape evaluated. Use inside map():
//   vec3 q = p - position;
//   BOUNDED(res, q, HUMAN_CENTER, HUMAN_RADIUS, sdHuman(q));
#define BOUND_MARGIN 0.2
#define BOUNDED(res, p, center, radius, call) { \
    float _b = length((p) - (center)) - (radius); \
    if (_b > BOUND_MARGIN) res = opUnion(res, vec2(_b, -1.0)); \
    else res = opUnion(res, call); \
}
