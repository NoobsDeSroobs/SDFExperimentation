#include <iostream>
#include "opengl.h"
#include "fileio.h"
using namespace glm;

// Camera
float g_theta = 0.0f;										// Horizontal angle
float g_phi = 0.0f;											// Vertical angle
vec3 g_camUp		= normalize(vec3(0.0f, 1.0f, 0.0f));	// The upward-vector of the image plane
vec3 g_camRight		= normalize(vec3(1.0f, 0.0f, 0.0f));	// The right-vector of the image plane
vec3 g_camForward	= cross(g_camRight, g_camUp);			// The forward-vector of the image plane
vec3 g_eye			= vec3(0.0f, 0.0f, -2.0f);				// The eye position in the world
float g_focalLength = 1.67f;								// Distance between eye and image-plane
float g_zNear		= 0.0f;									// Near plane distance from camera
float g_zFar		= 150.0f;								// Far plane distance from camera
float g_moveSpeed	= 0.005f;

// Raymarch parameters
int g_rmSteps		= 640;
float g_rmEpsilon	= 0.001f;

// Scene
vec4 g_skyColor 		= vec4(0.31f, 0.47f, 0.67f, 1.0f);
vec4 g_ambient			= vec4(0.15f, 0.2f, 0.32f, 1.0f);
vec3 g_light0Position 	= vec3(0.25f, 2.0f, 0.0f);
vec4 g_light0Color 		= vec4(0.67f, 0.87f, 0.93f, 1.0f);

const int g_windowWidth = 1920;
const int g_windowHeight = 1080;
float g_aspectRatio = g_windowWidth / (float)g_windowHeight;
sf::Window* window;
sf::Time SysTime;

void updateCamera(float dt)
{
	if(sf::Keyboard::isKeyPressed(sf::Keyboard::A))
		g_eye -= g_camRight * g_moveSpeed;
	else if(sf::Keyboard::isKeyPressed(sf::Keyboard::D))
		g_eye += g_camRight * g_moveSpeed;

	if(sf::Keyboard::isKeyPressed(sf::Keyboard::W))
		g_eye += g_camForward * g_moveSpeed;
	else if(sf::Keyboard::isKeyPressed(sf::Keyboard::S))
		g_eye -= g_camForward * g_moveSpeed;

	if(sf::Keyboard::isKeyPressed(sf::Keyboard::Space))
		g_eye += g_camUp * g_moveSpeed;
	else if(sf::Keyboard::isKeyPressed(sf::Keyboard::LControl))
		g_eye -= g_camUp * g_moveSpeed;

	if(sf::Keyboard::isKeyPressed(sf::Keyboard::LShift)) {
		g_moveSpeed = 0.05f;
	}else {
		g_moveSpeed = 0.01f;
	}

	if(sf::Keyboard::isKeyPressed(sf::Keyboard::Left))
		g_light0Position -= g_camRight * g_moveSpeed;
	else if(sf::Keyboard::isKeyPressed(sf::Keyboard::Right))
		g_light0Position += g_camRight * g_moveSpeed;

	if(sf::Keyboard::isKeyPressed(sf::Keyboard::Up))
		g_light0Position += g_camUp * g_moveSpeed;
	else if(sf::Keyboard::isKeyPressed(sf::Keyboard::Down))
		g_light0Position -= g_camUp * g_moveSpeed;

	sf::Vector2i mPos;
	mPos = sf::Mouse::getPosition();
	sf::Mouse::setPosition(sf::Vector2i(g_windowWidth / 2, g_windowHeight / 2));
	int dx = mPos.x - g_windowWidth / 2;
	int dy = mPos.y - g_windowHeight / 2;
	g_theta += dx * 0.001f;
	static const float TWO_PI = 6.28318530718f;
	if(g_theta > TWO_PI) g_theta -= TWO_PI;
	else if(g_theta < 0.0f) g_theta += TWO_PI;

	g_phi += dy * 0.001f;
	if(g_phi > TWO_PI) g_phi -= TWO_PI;
	else if(g_phi < 0.0f) g_phi += TWO_PI;

	float sintheta = sinf(g_theta);
	float costheta = cosf(g_theta);
	float sinphi = sinf(g_phi);
	float cosphi = cosf(g_phi);
	g_camForward = vec3(cosphi * sintheta, -sinphi, cosphi * costheta);
	g_camRight = vec3(costheta, 0.0f, -sintheta);
	g_camUp = normalize(cross(g_camForward, g_camRight));
}

std::ostream &operator<<(std::ostream &out, const vec3 &v)
{
	out<<"("<<v.x<<" "<<v.y<<" "<<v.z<<")";
	return out;
}

int main() {


	OpenGLHandler GLHandler = OpenGLHandler();
	if (!GLHandler.createContext("Raymarching Distance Fields", g_windowWidth, g_windowHeight, 0, 0, 0, false))
	{
		std::cout << "GlewINIT fgaile";
		return EXIT_FAILURE;
	}
	window = GLHandler.GetWindow();
	SysTime = sf::Time();

	sf::Mouse::setPosition(sf::Vector2i(g_windowWidth / 2, g_windowHeight / 2));
	//glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);

	std::string raymarch_vs, raymarch_fs;
	if (!readFile("D:/Projects/SDFOpenGL/data/raymarch.vs", raymarch_vs) ||
		!readFile("D:/Projects/SDFOpenGL/data/raymarch.fs", raymarch_fs))
	{
		std::cout <<  "Cant read shaders";
		return EXIT_FAILURE;
	}
	GLuint raymarchVsObj = GLHandler.compileShader(GL_VERTEX_SHADER, 1, raymarch_vs);
	GLuint raymarchFsObj = GLHandler.compileShader(GL_FRAGMENT_SHADER, 1, raymarch_fs);
	GLuint program0 = GLHandler.createProgram(raymarchVsObj, raymarchFsObj);
	glUseProgram(program0);

	// A quad extending from -1 to 1 on the x and y axis (the entire screen)
	GLfloat vertices[] = {
		-1.0f, -1.0f,
		-1.0f,  1.0f,
		 1.0f, -1.0f,
		 1.0f,  1.0f
	};

	GLuint vao;
	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);

	GLuint vbo;
	glGenBuffers(1, &vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

	GLuint positionAttrib = glGetAttribLocation(program0, "position");
	glEnableVertexAttribArray(positionAttrib);
	glVertexAttribPointer(positionAttrib, 2, GL_FLOAT, GL_FALSE, 0, 0);

	GLuint g_resolutionLoc	= glGetUniformLocation(program0, "g_resolution");
	GLuint g_camUpLoc		= glGetUniformLocation(program0, "g_camUp");
	GLuint g_camRightLoc	= glGetUniformLocation(program0, "g_camRight");
	GLuint g_camForwardLoc	= glGetUniformLocation(program0, "g_camForward");
	GLuint g_eyeLoc			= glGetUniformLocation(program0, "g_eye");
	GLuint g_focalLengthLoc	= glGetUniformLocation(program0, "g_focalLength");
	GLuint g_zNearLoc		= glGetUniformLocation(program0, "g_zNear");
	GLuint g_zFarLoc		= glGetUniformLocation(program0, "g_zFar");
	GLuint g_aspectRatioLoc	= glGetUniformLocation(program0, "g_aspectRatio");
	GLuint g_rmStepsLoc		= glGetUniformLocation(program0, "g_rmSteps");
	GLuint g_rmEpsilonLoc	= glGetUniformLocation(program0, "g_rmEpsilon");
	GLuint g_skyColorLoc	= glGetUniformLocation(program0, "g_skyColor");
	GLuint g_ambientLoc		= glGetUniformLocation(program0, "g_ambient");
	GLuint g_light0PosLoc	= glGetUniformLocation(program0, "g_light0Position");
	GLuint g_light0ColorLoc	= glGetUniformLocation(program0, "g_light0Color");
	
	glUniform2f(g_resolutionLoc,	g_windowWidth, g_windowHeight);
	glUniform1f(g_zNearLoc,			g_zNear);
	glUniform1f(g_zFarLoc,			g_zFar);
	glUniform1f(g_aspectRatioLoc,	g_aspectRatio);
	glUniform1f(g_rmEpsilonLoc,		g_rmEpsilon);
	glUniform1i(g_rmStepsLoc,		g_rmSteps);

	double renderTime = 0.0;
	double targetFrameTime = 1.0 / 60.0;
	while(window->isOpen())
	{
		updateCamera(renderTime);

		double renderStart = SysTime.asMilliseconds();
		glClearColor(0, 0, 0, 0);
		glClear(GL_COLOR_BUFFER_BIT);

		glUniform3fv(g_camUpLoc,			1, value_ptr(g_camUp));
		glUniform3fv(g_camRightLoc,			1, value_ptr(g_camRight));
		glUniform3fv(g_camForwardLoc,		1, value_ptr(g_camForward));
		glUniform3fv(g_eyeLoc,				1, value_ptr(g_eye));
		glUniform1f(g_focalLengthLoc,		g_focalLength);
		glUniform4fv(g_skyColorLoc,			1, value_ptr(g_skyColor));
		glUniform4fv(g_ambientLoc,			1, value_ptr(g_ambient));
		glUniform3fv(g_light0PosLoc, 1, value_ptr(g_eye));// g_light0Position));
		glUniform4fv(g_light0ColorLoc,		1, value_ptr(g_light0Color));

		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

		window->display();
		renderTime = SysTime.asMilliseconds() - renderStart;
		if(renderTime < targetFrameTime)
			sf::sleep(sf::milliseconds(targetFrameTime - renderTime));

		//glfwPollEvents();

		if (sf::Keyboard::isKeyPressed(sf::Keyboard::Escape))
			window->close();
	}

	GLHandler.destroyContext();
	return EXIT_SUCCESS;
}
