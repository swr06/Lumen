#version 450 core

layout(RGBA8, binding = 0) uniform image3D o_VoxelVolume;

uniform sampler2D u_AlbedoMap;
uniform sampler2D u_ShadowMap;
uniform vec3 u_SunDirection;
uniform vec3 u_F_PlayerPosition;

in vec3 g_WorldPosition;
in vec3 g_Normal;

void main() 
{
	ivec3 VoxelVolumeSize = imageSize(o_VoxelVolume);

	if (g_WorldPosition.x < float(VoxelVolumeSize.x) &&
		g_WorldPosition.y < float(VoxelVolumeSize.y) &&
		g_WorldPosition.z < float(VoxelVolumeSize.z))
	{
		vec3 EstimatedAverageAlbedo = textureLod(u_AlbedoMap, vec2(0.5f), 8.0f).xyz;
		vec3 Color = EstimatedAverageAlbedo * 2.0f;
		float SunDiffuse = max(0.01f, dot(g_Normal, u_SunDirection));
		vec3 Voxel = (g_WorldPosition / vec3(VoxelVolumeSize)) * 0.5f + 0.5f;
		ivec3 StoreLoc = ivec3(Voxel * VoxelVolumeSize);
		imageStore(o_VoxelVolume, StoreLoc, vec4(Color, 1.0f));
	}
}