// Red test balls fired from the camera (left mouse button). Rust simulates them and sends
// each as vec4(world position, radius) in g_balls; radius 0 means the slot is empty. Each
// ball melts into everything in the scene, shape and colour, so you can see how shapes blend.

// Adds all active balls to the surface found so far
Surface addBalls(Surface nearest_surface, vec3 world_point) {
    for (int ball_index = 0; ball_index < MAX_BALLS; ball_index++) {
        vec4 ball_position_and_radius = g_balls[ball_index];
        vec3 ball_world_position = ball_position_and_radius.xyz;
        float ball_radius = ball_position_and_radius.w;
        if (ball_radius <= 0.0) continue;

        Surface ball_surface = Surface(sdSphere(world_point - ball_world_position, ball_radius),
                                       COLOR_BALL);
        // The blend distance follows the radius, so a ball fading out lets go smoothly
        nearest_surface = opSmoothUnion(nearest_surface, ball_surface, ball_radius);
    }
    return nearest_surface;
}
