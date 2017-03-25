#include "opengl.h"
#include <vector>
#include <iostream>

OpenGLHandler::OpenGLHandler() {
}

bool OpenGLHandler::createContext(const char *title, int width, int height,
int depthbits, int stencilbits, int fsaa, bool fullscreen)
{
	window = new sf::Window();
	GLuint initStatus = glewInit();
	if (initStatus != 0)
	{
		std::cout <<  initStatus;
		return false;
	}
	sf::ContextSettings settings(depthbits, stencilbits, fsaa, OPENGL_VERSION_MAJOR, OPENGL_VERSION_MINOR);


	window->create(sf::VideoMode(width, height), title, sf::Style::Default, settings);
	if (!window)
	{
		return false;
	}

	//if (!shaders.loadFromFile("D:/Projects/SDFOpenGL/data/raymarch.fs", "D:/Projects/SDFOpenGL/data/raymarch.fs"))
	//{
	//	return false;
	//	// error...
	//}
	//sf::Shader::bind(&shaders);
	return true;
}

void OpenGLHandler::destroyContext()
{
	sf::Shader::bind(NULL);
	window->close();
}

GLuint OpenGLHandler::compileShader(GLenum shaderType, GLsizei count, const std::string &shaderSrc)
{
	const char *shaderSrcStr = shaderSrc.c_str();
	GLuint shader = glCreateShader(shaderType);

	if(shader == GL_INVALID_ENUM) {
		std::cout <<  "Invalid";
		return -1;
	}

	if(shader == 0) {
		std::cout <<  "ShaderFailed";
	}

	glShaderSource(shader, count, &shaderSrcStr, NULL);
	glCompileShader(shader);

	// Check status
	GLint status;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
	if(status == GL_FALSE)
	{
		GLint infoLogLength;
		glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLogLength);
		GLchar *infoLog = new GLchar[infoLogLength + 1];
		glGetShaderInfoLog(shader, infoLogLength, NULL, infoLog);
		std::cerr<<"Compile failure: "<<infoLog<<std::endl;
		delete[] infoLog;
	}

	return shader;
}

GLuint OpenGLHandler::createProgram(GLuint vertexShader, GLuint fragmentShader, GLuint geometryShader)
{
	GLuint program = glCreateProgram();

	if(vertexShader != 0) glAttachShader(program, vertexShader);
	if(fragmentShader != 0) glAttachShader(program, fragmentShader);
	if(geometryShader != 0) glAttachShader(program, geometryShader);

	glLinkProgram(program);

	// Check for (and print) errors
	GLint status;
	glGetProgramiv(program, GL_LINK_STATUS, &status);
	if(status == GL_FALSE)
	{
		GLint infoLogLength;
		glGetProgramiv(program, GL_INFO_LOG_LENGTH, &infoLogLength);

		GLchar *strInfoLog = new GLchar[infoLogLength + 1];
		glGetProgramInfoLog(program, infoLogLength, NULL, strInfoLog);
		std::cerr<<"Linker failure: "<<std::endl<<strInfoLog<<std::endl;
		delete[] strInfoLog;
	}

	if(vertexShader != 0) glDetachShader(program, vertexShader);
	if(fragmentShader != 0) glDetachShader(program, fragmentShader);
	if(geometryShader != 0) glDetachShader(program, geometryShader);

	return program;
}


sf::Window* OpenGLHandler::GetWindow() {
	return window;
}