use glam::Vec3;
use miniquad::*;
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

#[repr(C)]
struct Uniforms {
    resolution: [f32; 2],
    cam_up: [f32; 3],
    cam_right: [f32; 3],
    cam_forward: [f32; 3],
    eye: [f32; 3],
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
    ctx: Box<dyn RenderingBackend>,
    pipeline: Pipeline,
    bindings: Bindings,
    keys: Keys,
    eye: Vec3,
    light: Vec3,
    theta: f32, // yaw
    phi: f32,   // pitch, positive looks up
    start: Instant,
    last: Instant,
    fps_since: Instant,
    fps_frames: u32,
}

impl Stage {
    fn new() -> Stage {
        let mut ctx = window::new_rendering_backend();

        // A quad covering the whole screen
        let vertices: [f32; 8] = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0];
        let vertex_buffer = ctx.new_buffer(
            BufferType::VertexBuffer,
            BufferUsage::Immutable,
            BufferSource::slice(&vertices),
        );
        let indices: [u16; 6] = [0, 1, 2, 0, 2, 3];
        let index_buffer = ctx.new_buffer(
            BufferType::IndexBuffer,
            BufferUsage::Immutable,
            BufferSource::slice(&indices),
        );
        let bindings = Bindings {
            vertex_buffers: vec![vertex_buffer],
            index_buffer,
            images: vec![],
        };

        let shader = ctx
            .new_shader(
                ShaderSource::Glsl {
                    vertex: include_str!("../shaders/raymarch.vs"),
                    fragment: include_str!("../shaders/raymarch.fs"),
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
                        ],
                    },
                },
            )
            .unwrap_or_else(|e| panic!("shader error: {e:?}"));

        let pipeline = ctx.new_pipeline(
            &[BufferLayout::default()],
            &[VertexAttribute::new("position", VertexFormat::Float2)],
            shader,
            PipelineParams::default(),
        );

        window::set_cursor_grab(true);
        window::show_mouse(false);

        let now = Instant::now();
        Stage {
            ctx,
            pipeline,
            bindings,
            keys: Keys::default(),
            eye: Vec3::new(0.0, 0.5, -4.0),
            light: Vec3::new(0.25, 3.0, -1.0),
            theta: 0.0,
            phi: 0.0,
            start: now,
            last: now,
            fps_since: now,
            fps_frames: 0,
        }
    }

    /// (forward, right, up) from yaw/pitch.
    fn basis(&self) -> (Vec3, Vec3, Vec3) {
        let (st, ct) = self.theta.sin_cos();
        let (sp, cp) = self.phi.sin_cos();
        let forward = Vec3::new(cp * st, sp, cp * ct);
        let right = Vec3::new(ct, 0.0, -st);
        let up = forward.cross(right);
        (forward, right, up)
    }

    fn step(&mut self, dt: f32) {
        let (forward, right, _) = self.basis();
        let k = &self.keys;
        let axis = |pos: bool, neg: bool| pos as i32 as f32 - neg as i32 as f32;
        let speed = MOVE_SPEED * if k.shift { FAST_MULTIPLIER } else { 1.0 } * dt;

        self.eye += right * axis(k.d, k.a) * speed;
        self.eye += forward * axis(k.w, k.s) * speed;
        self.eye += Vec3::Y * axis(k.space, k.ctrl) * speed;

        self.light += right * axis(k.right, k.left) * speed;
        self.light += Vec3::Y * axis(k.up, k.down) * speed;
    }

    fn set_key(&mut self, key: KeyCode, down: bool) {
        let k = &mut self.keys;
        match key {
            KeyCode::W => k.w = down,
            KeyCode::A => k.a = down,
            KeyCode::S => k.s = down,
            KeyCode::D => k.d = down,
            KeyCode::Up => k.up = down,
            KeyCode::Down => k.down = down,
            KeyCode::Left => k.left = down,
            KeyCode::Right => k.right = down,
            KeyCode::Space => k.space = down,
            KeyCode::LeftControl => k.ctrl = down,
            KeyCode::LeftShift => k.shift = down,
            _ => {}
        }
    }
}

impl EventHandler for Stage {
    fn update(&mut self) {
        let now = Instant::now();
        let dt = (now - self.last).as_secs_f32();
        self.last = now;
        self.step(dt);
    }

    fn draw(&mut self) {
        let (forward, right, up) = self.basis();
        let (w, h) = window::screen_size();
        let uniforms = Uniforms {
            resolution: [w, h],
            cam_up: up.to_array(),
            cam_right: right.to_array(),
            cam_forward: forward.to_array(),
            eye: self.eye.to_array(),
            focal_length: FOCAL_LENGTH,
            z_near: Z_NEAR,
            z_far: Z_FAR,
            rm_steps: RM_STEPS,
            rm_epsilon: RM_EPSILON,
            sky_color: [0.31, 0.47, 0.67, 1.0],
            ambient: [0.15, 0.2, 0.32, 1.0],
            light0_position: self.light.to_array(),
            light0_color: [0.67, 0.87, 0.93, 1.0],
            time: self.start.elapsed().as_secs_f32(),
        };

        self.ctx.begin_default_pass(PassAction::Nothing);
        self.ctx.apply_pipeline(&self.pipeline);
        self.ctx.apply_bindings(&self.bindings);
        self.ctx.apply_uniforms(UniformsSource::table(&uniforms));
        self.ctx.draw(0, 6, 1);
        self.ctx.end_render_pass();
        self.ctx.commit_frame();

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

    fn raw_mouse_motion(&mut self, dx: f32, dy: f32) {
        self.theta = (self.theta + dx * MOUSE_SENSITIVITY).rem_euclid(std::f32::consts::TAU);
        let limit = std::f32::consts::FRAC_PI_2 - 0.01;
        self.phi = (self.phi - dy * MOUSE_SENSITIVITY).clamp(-limit, limit);
    }

    fn key_down_event(&mut self, key: KeyCode, _mods: KeyMods, _repeat: bool) {
        self.set_key(key, true);
        if key == KeyCode::Escape {
            window::request_quit();
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
