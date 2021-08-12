#pragma once
#include <glm/glm.hpp>
#include <glad/glad.h>

namespace Lumen
{
	struct Vertex
	{
		glm::vec3 position;
		glm::vec3 normals;
		GLuint texcoords;
		glm::vec3 tangent;
		uint16_t TEXID1;
		uint16_t TEXID2;
	};
}