#version 450 core

#define VOXEL_SIZE 2

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

	if (g_WorldPosition.x < float(VoxelVolumeSize.x / float(VOXEL_SIZE)) &&
		g_WorldPosition.y < float(VoxelVolumeSize.y / float(VOXEL_SIZE)) &&
		g_WorldPosition.z < float(VoxelVolumeSize.z / float(VOXEL_SIZE)))
	{
		// Estimate albedo from sampling a lower lod at a few coords
		// this can be precomputed but whatever 
		vec3 EstimatedAverageAlbedo = textureLod(u_AlbedoMap, vec2(0.5f), 8.0f).xyz +
									  textureLod(u_AlbedoMap, vec2(0.25f), 8.0f).xyz +
									  textureLod(u_AlbedoMap, vec2(0.75f), 8.0f).xyz + 
									  textureLod(u_AlbedoMap, vec2(1.0f), 8.0f).xyz +
									  textureLod(u_AlbedoMap, vec2(0.0f), 8.0f).xyz;
		EstimatedAverageAlbedo /= 5.0f;
		vec3 Color = EstimatedAverageAlbedo * 2.0f;
		vec3 Voxel = (g_WorldPosition / vec3(VoxelVolumeSize / VOXEL_SIZE)) * 0.5f + 0.5f;
		ivec3 StoreLoc = ivec3(Voxel * VoxelVolumeSize);
		imageStore(o_VoxelVolume, StoreLoc, vec4(Color, 1.0f));
	}
}