// Red test balls fired from the camera (left mouse button). Rust simulates them and sends
// each as vec4(world position, radius) in g_balls; radius 0 means the slot is empty. Each
// ball melts into everything in the scene, so you can see how shapes blend.

#define MAT_BALL 6.0

// Adds all active balls to the surface found so far (distance, material id)
vec2 addBalls(vec2 nearest_surface, vec3 world_point) {
    for (int ball_index = 0; ball_index < MAX_BALLS; ball_index++) {
        vec4 ball_position_and_radius = g_balls[ball_index];
        vec3 ball_world_position = ball_position_and_radius.xyz;
        float ball_radius = ball_position_and_radius.w;
        if (ball_radius <= 0.0) continue;

        float distance_to_ball = sdSphere(world_point - ball_world_position, ball_radius);
        // The blend distance follows the radius, so a ball fading out lets go smoothly
        float blended_distance = opSmoothUnion(nearest_surface.x, distance_to_ball, ball_radius);
        float material_id = distance_to_ball < nearest_surface.x ? MAT_BALL : nearest_surface.y;
        nearest_surface = vec2(blended_distance, material_id);
    }
    return nearest_surface;
}
