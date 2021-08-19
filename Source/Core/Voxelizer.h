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
		void VoxelizeScene(FPSCamera* camera, GLuint shadow_map, glm::vec3 sun_dir, std::vector<Entity*> entities, glm::mat4 LightVP);
		void GenerateDistanceField();
		void Recompile();

		GLuint m_VoxelVolume = 0;
		GLuint m_DistanceFieldVolume = 0;

		GLClasses::Shader		 m_Voxelizer;
		GLClasses::ComputeShader m_ClearShader;
		GLClasses::ComputeShader m_DistanceShaderX;
		GLClasses::ComputeShader m_DistanceShaderY;
		GLClasses::ComputeShader m_DistanceShaderZ;
	};
}