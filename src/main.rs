use glam::Vec3;
use miniquad::*;
use std::path::{Path, PathBuf};
use std::time::Instant;

// Raymarch parameters
const RM_STEPS: i32 = 640;
const RM_EPSILON: f32 = 0.001;
const Z_NEAR: f32 = 0.0;
const Z_FAR: f32 = 150.0;
const FOCAL_LENGTH: f32 = 1.67;

const MOUSE_SENSITIVITY: f32 = 0.002;
const MOVE_SPEED: f32 = 3.0;
const FAST_MULTIPLIER: f32 = 5.0;

// Test balls (left click to fire). Must match MAX_BALLS in raymarch.fs.
const MAX_BALLS: usize = 8;
const BALL_RADIUS: f32 = 0.3;
const BALL_LIFETIME: f32 = 10.0;
const BALL_FADE: f32 = 0.5; // seconds spent shrinking away at the end of its life
const BALL_SPEED: f32 = 8.0;
const BALL_GRAVITY: f32 = 9.8;
const BALL_BOUNCINESS: f32 = 0.8; // fraction of vertical speed kept after hitting the floor
const FLOOR_Y: f32 = -1.0; // the ground plane in map()

#[repr(C)]
struct Uniforms {
    resolution: [f32; 2],
    cam_up: [f32; 3],
    cam_right: [f32; 3],
    cam_forward: [f32; 3],
    camera_position: [f32; 3],
    focal_length: f32,
    z_near: f32,
    z_far: f32,
    rm_steps: i32,
    rm_epsilon: f32,
    sky_color: [f32; 4],
    ambient: [f32; 4],
    light0_position: [f32; 3],
    light0_color: [f32; 4],
    time: f32,
    balls: [[f32; 4]; MAX_BALLS], // xyz position, w radius (0 = unused slot)
}

/// A test ball shot from the camera.
struct Ball {
    position: Vec3,
    velocity: Vec3,
    age_seconds: f32,
}

impl Ball {
    /// Radius, shrinking to nothing over the last BALL_FADE seconds
    fn radius(&self) -> f32 {
        BALL_RADIUS * ((BALL_LIFETIME - self.age_seconds) / BALL_FADE).clamp(0.0, 1.0)
    }
}

/// The shaders folder: `./shaders` if present, else the one next to Cargo.toml.
fn find_shader_dir() -> PathBuf {
    let local_dir = PathBuf::from("shaders");
    if local_dir.is_dir() {
        local_dir
    } else {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("shaders")
    }
}

/// Reads a GLSL file and expands `#include "file"` lines (relative to `shader_dir`), since GLSL
/// has no include of its own.
fn load_glsl(shader_dir: &Path, name: &str, depth: u32) -> Result<String, String> {
    if depth > 8 {
        return Err(format!("{name}: includes nested too deeply (cycle?)"));
    }
    let path = shader_dir.join(name);
    let source = std::fs::read_to_string(&path).map_err(|error| format!("{}: {error}", path.display()))?;
    let mut combined = String::with_capacity(source.len());
    for line in source.lines() {
        match line.trim().strip_prefix("#include") {
            Some(rest) => {
                let file = rest.trim().trim_matches('"');
                combined.push_str(&load_glsl(shader_dir, file, depth + 1)?);
            }
            None => combined.push_str(line),
        }
        combined.push('\n');
    }
    Ok(combined)
}

fn build_pipeline(backend: &mut dyn RenderingBackend, shader_dir: &Path) -> Result<Pipeline, String> {
    let vertex = load_glsl(shader_dir, "raymarch.vs", 0)?;
    let fragment = load_glsl(shader_dir, "raymarch.fs", 0)?;
    let shader = backend
        .new_shader(
            ShaderSource::Glsl {
                vertex: &vertex,
                fragment: &fragment,
            },
            ShaderMeta {
                images: vec![],
                uniforms: UniformBlockLayout {
                    uniforms: vec![
                        UniformDesc::new("g_resolution", UniformType::Float2),
                        UniformDesc::new("g_camUp", UniformType::Float3),
                        UniformDesc::new("g_camRight", UniformType::Float3),
                        UniformDesc::new("g_camForward", UniformType::Float3),
                        UniformDesc::new("g_eye", UniformType::Float3),
                        UniformDesc::new("g_focalLength", UniformType::Float1),
                        UniformDesc::new("g_zNear", UniformType::Float1),
                        UniformDesc::new("g_zFar", UniformType::Float1),
                        UniformDesc::new("g_rmSteps", UniformType::Int1),
                        UniformDesc::new("g_rmEpsilon", UniformType::Float1),
                        UniformDesc::new("g_skyColor", UniformType::Float4),
                        UniformDesc::new("g_ambient", UniformType::Float4),
                        UniformDesc::new("g_light0Position", UniformType::Float3),
                        UniformDesc::new("g_light0Color", UniformType::Float4),
                        UniformDesc::new("g_time", UniformType::Float1),
                        UniformDesc::new("g_balls", UniformType::Float4).array(MAX_BALLS),
                    ],
                },
            },
        )
        .map_err(|error| error.to_string())?;

    Ok(backend.new_pipeline(
        &[BufferLayout::default()],
        &[VertexAttribute::new("position", VertexFormat::Float2)],
        shader,
        PipelineParams::default(),
    ))
}

#[derive(Default)]
struct Keys {
    w: bool,
    a: bool,
    s: bool,
    d: bool,
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    space: bool,
    ctrl: bool,
    shift: bool,
}

struct Stage {
    backend: Box<dyn RenderingBackend>,
    pipeline: Pipeline,
    shader_dir: PathBuf,
    bindings: Bindings,
    keys: Keys,
    camera_position: Vec3,
    light_position: Vec3,
    yaw_radians: f32,
    pitch_radians: f32, // positive looks up
    start: Instant,
    balls: Vec<Ball>,
    last: Instant,
    fps_since: Instant,
    fps_frames: u32,
}

impl Stage {
    fn new() -> Stage {
        let mut backend = window::new_rendering_backend();

        // A quad covering the whole screen
        let vertices: [f32; 8] = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0];
        let vertex_buffer = backend.new_buffer(
            BufferType::VertexBuffer,
            BufferUsage::Immutable,
            BufferSource::slice(&vertices),
        );
        let indices: [u16; 6] = [0, 1, 2, 0, 2, 3];
        let index_buffer = backend.new_buffer(
            BufferType::IndexBuffer,
            BufferUsage::Immutable,
            BufferSource::slice(&indices),
        );
        let bindings = Bindings {
            vertex_buffers: vec![vertex_buffer],
            index_buffer,
            images: vec![],
        };

        let shader_dir = find_shader_dir();
        let pipeline = build_pipeline(backend.as_mut(), &shader_dir).unwrap_or_else(|error| panic!("{error}"));

        window::set_cursor_grab(true);
        window::show_mouse(false);

        let now = Instant::now();
        Stage {
            backend,
            pipeline,
            shader_dir,
            bindings,
            keys: Keys::default(),
            camera_position: Vec3::new(0.0, 0.5, -4.0),
            light_position: Vec3::new(0.25, 3.0, -1.0),
            yaw_radians: 0.0,
            pitch_radians: 0.0,
            start: now,
            balls: Vec::new(),
            last: now,
            fps_since: now,
            fps_frames: 0,
        }
    }

    /// (forward, right, up) from yaw/pitch.
    fn basis(&self) -> (Vec3, Vec3, Vec3) {
        let (sin_yaw, cos_yaw) = self.yaw_radians.sin_cos();
        let (sin_pitch, cos_pitch) = self.pitch_radians.sin_cos();
        let forward = Vec3::new(cos_pitch * sin_yaw, sin_pitch, cos_pitch * cos_yaw);
        let right = Vec3::new(cos_yaw, 0.0, -sin_yaw);
        let up = forward.cross(right);
        (forward, right, up)
    }

    fn step(&mut self, delta_time: f32) {
        let (forward, right, _) = self.basis();
        let keys = &self.keys;
        let axis = |positive: bool, negative: bool| positive as i32 as f32 - negative as i32 as f32;
        let step_distance = MOVE_SPEED * if keys.shift { FAST_MULTIPLIER } else { 1.0 } * delta_time;

        self.camera_position += right * axis(keys.d, keys.a) * step_distance;
        self.camera_position += forward * axis(keys.w, keys.s) * step_distance;
        self.camera_position += Vec3::Y * axis(keys.space, keys.ctrl) * step_distance;

        self.light_position += right * axis(keys.right, keys.left) * step_distance;
        self.light_position += Vec3::Y * axis(keys.up, keys.down) * step_distance;
    }

    /// Fires a ball straight ahead from the camera; the oldest goes if all slots are in use.
    fn fire_ball(&mut self) {
        if self.balls.len() >= MAX_BALLS {
            self.balls.remove(0);
        }
        let (forward, _, _) = self.basis();
        self.balls.push(Ball {
            position: self.camera_position + forward * 0.5,
            velocity: forward * BALL_SPEED,
            age_seconds: 0.0,
        });
    }

    fn step_balls(&mut self, delta_time: f32) {
        for ball in &mut self.balls {
            ball.age_seconds += delta_time;
            ball.velocity.y -= BALL_GRAVITY * delta_time;
            ball.position += ball.velocity * delta_time;
            // Bounce on the floor (the only thing the simulation collides with)
            let floor = FLOOR_Y + BALL_RADIUS;
            if ball.position.y < floor && ball.velocity.y < 0.0 {
                ball.position.y = floor;
                ball.velocity.y = -ball.velocity.y * BALL_BOUNCINESS;
            }
        }
        self.balls.retain(|ball| ball.age_seconds < BALL_LIFETIME);
    }

    fn ball_uniforms(&self) -> [[f32; 4]; MAX_BALLS] {
        let mut ball_slots = [[0.0; 4]; MAX_BALLS];
        for (slot, ball) in ball_slots.iter_mut().zip(&self.balls) {
            let position = ball.position;
            *slot = [position.x, position.y, position.z, ball.radius()];
        }
        ball_slots
    }

    fn set_key(&mut self, key: KeyCode, down: bool) {
        let keys = &mut self.keys;
        match key {
            KeyCode::W => keys.w = down,
            KeyCode::A => keys.a = down,
            KeyCode::S => keys.s = down,
            KeyCode::D => keys.d = down,
            KeyCode::Up => keys.up = down,
            KeyCode::Down => keys.down = down,
            KeyCode::Left => keys.left = down,
            KeyCode::Right => keys.right = down,
            KeyCode::Space => keys.space = down,
            KeyCode::LeftControl => keys.ctrl = down,
            KeyCode::LeftShift => keys.shift = down,
            _ => {}
        }
    }
}

impl EventHandler for Stage {
    fn update(&mut self) {
        let now = Instant::now();
        let delta_time = (now - self.last).as_secs_f32();
        self.last = now;
        self.step(delta_time);
        self.step_balls(delta_time);
    }

    fn mouse_button_down_event(&mut self, button: MouseButton, _x: f32, _y: f32) {
        if button == MouseButton::Left {
            self.fire_ball();
        }
    }

    fn draw(&mut self) {
        let (forward, right, up) = self.basis();
        let (width, height) = window::screen_size();
        let uniforms = Uniforms {
            resolution: [width, height],
            cam_up: up.to_array(),
            cam_right: right.to_array(),
            cam_forward: forward.to_array(),
            camera_position: self.camera_position.to_array(),
            focal_length: FOCAL_LENGTH,
            z_near: Z_NEAR,
            z_far: Z_FAR,
            rm_steps: RM_STEPS,
            rm_epsilon: RM_EPSILON,
            sky_color: [0.31, 0.47, 0.67, 1.0],
            ambient: [0.15, 0.2, 0.32, 1.0],
            light0_position: self.light_position.to_array(),
            light0_color: [0.67, 0.87, 0.93, 1.0],
            time: self.start.elapsed().as_secs_f32(),
            balls: self.ball_uniforms(),
        };

        self.backend.begin_default_pass(PassAction::Nothing);
        self.backend.apply_pipeline(&self.pipeline);
        self.backend.apply_bindings(&self.bindings);
        self.backend.apply_uniforms(UniformsSource::table(&uniforms));
        self.backend.draw(0, 6, 1);
        self.backend.end_render_pass();
        self.backend.commit_frame();

        self.fps_frames += 1;
        let elapsed = self.fps_since.elapsed().as_secs_f32();
        if elapsed >= 1.0 {
            println!(
                "{:.1} FPS ({:.2} ms/frame)",
                self.fps_frames as f32 / elapsed,
                elapsed * 1000.0 / self.fps_frames as f32
            );
            self.fps_since = Instant::now();
            self.fps_frames = 0;
        }
    }

    fn raw_mouse_motion(&mut self, delta_x: f32, delta_y: f32) {
        self.yaw_radians = (self.yaw_radians + delta_x * MOUSE_SENSITIVITY).rem_euclid(std::f32::consts::TAU);
        let pitch_limit_radians = std::f32::consts::FRAC_PI_2 - 0.01;
        self.pitch_radians = (self.pitch_radians - delta_y * MOUSE_SENSITIVITY).clamp(-pitch_limit_radians, pitch_limit_radians);
    }

    fn key_down_event(&mut self, key: KeyCode, _mods: KeyMods, repeat: bool) {
        self.set_key(key, true);
        match key {
            KeyCode::Escape => window::request_quit(),
            KeyCode::R if !repeat => match build_pipeline(self.backend.as_mut(), &self.shader_dir) {
                Ok(pipeline) => {
                    self.backend.delete_pipeline(self.pipeline);
                    self.pipeline = pipeline;
                    println!("Shaders reloaded");
                }
                Err(error) => eprintln!("Shader reload failed, keeping the old one:\n{error}"),
            },
            _ => {}
        }
    }

    fn key_up_event(&mut self, key: KeyCode, _mods: KeyMods) {
        self.set_key(key, false);
    }
}

fn main() {
    let conf = conf::Conf {
        window_title: "Raymarching Distance Fields".to_string(),
        window_width: 1280,
        window_height: 720,
        ..Default::default()
    };
    miniquad::start(conf, || Box::new(Stage::new()));
}
