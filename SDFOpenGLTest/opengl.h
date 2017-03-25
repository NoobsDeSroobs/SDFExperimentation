#pragma once

/*
Provides functions for context creation and destruction, as well as OpenGL helper functions such
as compiling shaders and GLSL programs.
*/

#include <GL\glew.h>// Context
#include <SFML\Graphics.hpp>
#include <SFML\Main.hpp>
#include <SFML\OpenGL.hpp>
#include <SFML\System.hpp>
#include <SFML\Window.hpp>
#include <glm/glm.hpp>			// OpenGL mathematics
#include <glm/gtc/type_ptr.hpp> // for value_ptr(matrix)
#include <string>

const int OPENGL_VERSION_MAJOR = 3;
const int OPENGL_VERSION_MINOR = 1; 
class OpenGLHandler
{
public:
	OpenGLHandler();
	OpenGLHandler(const OpenGLHandler& OtherHandler);
	bool createContext(const char *title, int w, int h, int depthbits, int stencilbits, int fsaa, bool fullscreen);
	void destroyContext();
	GLuint compileShader(GLenum shaderType, GLsizei count, const std::string &shaderSrc);
	GLuint createProgram(GLuint vertexShader, GLuint fragmentShader, GLuint geometryShader = 0);
	sf::Window* GetWindow();
private:
	sf::Window* window;
	sf::Shader shaders;
};