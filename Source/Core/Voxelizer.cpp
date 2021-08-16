#include "Voxelizer.h"

#define VOXEL_VOLUME_X 192
#define VOXEL_VOLUME_Y 192
#define VOXEL_VOLUME_Z 192

void Lumen::VoxelVolume::CreateVoxelVolume()
{
	m_Voxelizer.CreateShaderProgramFromFile("Core/Shaders/Voxelization/Voxelization.vert", "Core/Shaders/Voxelization/Voxelization.frag", "Core/Shaders/Voxelization/Voxelization.geom");
	m_Voxelizer.CompileShaders();
	m_ClearShader.CreateComputeShader("Core/Shaders/Voxelization/ClearData.comp");
	m_ClearShader.Compile();

	glGenTextures(1, &m_VoxelVolume);
	glBindTexture(GL_TEXTURE_3D, m_VoxelVolume);
	glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
	glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA, VOXEL_VOLUME_X, VOXEL_VOLUME_Y, VOXEL_VOLUME_Z, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
}

void Lumen::VoxelVolume::VoxelizeScene(FPSCamera* camera, GLuint shadow_map, glm::vec3 sun_dir, std::vector<Entity*> entities)
{
	glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_BLEND);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glUseProgram(0);

	int GROUP_SIZE = 8;

	m_ClearShader.Use();
	glBindImageTexture(0, m_VoxelVolume, 0, GL_TRUE, 0, GL_READ_WRITE, GL_RGBA8);
	glDispatchCompute(VOXEL_VOLUME_X / GROUP_SIZE, VOXEL_VOLUME_Y / GROUP_SIZE, VOXEL_VOLUME_Z / GROUP_SIZE);
	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

	m_Voxelizer.Use();
	glViewport(0, 0, VOXEL_VOLUME_X, VOXEL_VOLUME_Z);
	m_Voxelizer.SetMatrix4("u_ViewProjection", camera->GetViewProjection());
	m_Voxelizer.SetInteger("u_AlbedoTexture", 0);
	m_Voxelizer.SetInteger("u_ShadowMap", 6);
	m_Voxelizer.SetVector3f("u_SunDirection", glm::normalize(sun_dir));
	m_Voxelizer.SetVector3f("u_gVolumeSize", glm::vec3(VOXEL_VOLUME_X, VOXEL_VOLUME_Y, VOXEL_VOLUME_Z));
	m_Voxelizer.SetVector3f("u_PlayerPosition", camera->GetPosition());
	m_Voxelizer.SetVector3f("u_F_PlayerPosition", camera->GetPosition());

	glBindImageTexture(0, m_VoxelVolume, 0, GL_TRUE, 0, GL_READ_WRITE, GL_RGBA8);

	glActiveTexture(GL_TEXTURE6);
	glBindTexture(GL_TEXTURE_2D, shadow_map);

	for (auto& e : entities)
	{
		RenderEntity(*e, m_Voxelizer);
	}

	glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glUseProgram(0);
}
