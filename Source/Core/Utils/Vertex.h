#pragma once
#include <glm/glm.hpp>

namespace Lumen
{
	struct Vertex
	{
		glm::vec3 position;
		glm::vec3 normals;
		glm::vec2 tex_coords;
		glm::vec3 tangent;
		uint16_t TEXID1;
		uint16_t TEXID2;
	};
}