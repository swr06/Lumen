#pragma once

#include "ModelRenderer.h"
#include "Mesh.h"
#include "Object.h"
#include "Entity.h"
#include "FpsCamera.h"
#include "GLClasses/ComputeShader.h"

namespace Lumen
{
	class VoxelVolume
	{
	public : 
		void CreateVoxelVolume();
		void VoxelizeScene(FPSCamera* camera, GLuint shadow_map, glm::vec3 sun_dir, std::vector<Entity*> entities);

		GLuint m_VoxelVolume = 0;
		GLClasses::Shader m_Voxelizer;
		GLClasses::ComputeShader m_ClearShader;
	};
}