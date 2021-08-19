#version 450 core

#define VOXEL_SIZE 1

layout(RGBA8, binding = 0) uniform image3D o_VoxelVolume;

uniform sampler2D u_AlbedoMap;
uniform sampler2D u_ShadowMap;
uniform vec3 u_SunDirection;
uniform vec3 u_F_PlayerPosition;

uniform mat4 u_LightVP;

in vec3 g_WorldPosition;
in vec3 g_Normal;

vec4 smoothfilter(in sampler2D tex, in vec2 uv) 
{
    vec2 resolution = textureSize(tex, 0);
	uv = uv*resolution + 0.5;
	vec2 iuv = floor(uv);
	vec2 fuv = fract(uv);
	uv = iuv + fuv*fuv*fuv*(fuv*(fuv*6.0-15.0)+10.0);
	uv = (uv - 0.5)/resolution;
	return textureLod(tex, uv, 0.0);
}

float ComputeDirectionalShadow(vec3 WorldPosition) 
{
	vec4 ProjectionCoordinates = u_LightVP * vec4(WorldPosition, 1.0f);
	ProjectionCoordinates.xyz = ProjectionCoordinates.xyz / ProjectionCoordinates.w; // Perspective division is not really needed for orthagonal projection but whatever
    ProjectionCoordinates.xyz = ProjectionCoordinates.xyz * 0.5f + 0.5f;
	float shadow = 0.0;

	if (ProjectionCoordinates.z > 1.0 || ProjectionCoordinates.x > 1.0f || ProjectionCoordinates.y > 1.0f ||
		ProjectionCoordinates.x < 0.0f || ProjectionCoordinates.y < 0.0f)
	{
		return 0.0f;
	}

    float Depth = ProjectionCoordinates.z;
	return float(smoothfilter(u_ShadowMap, ProjectionCoordinates.xy).x < ProjectionCoordinates.z - 0.001);
}

void main() 
{
	ivec3 VoxelVolumeSize = imageSize(o_VoxelVolume);

	if (g_WorldPosition.x < float(VoxelVolumeSize.x / float(VOXEL_SIZE)) &&
		g_WorldPosition.y < float(VoxelVolumeSize.y / float(VOXEL_SIZE)) &&
		g_WorldPosition.z < float(VoxelVolumeSize.z / float(VOXEL_SIZE)))
	{
		// Sampling the shadow map is expensive! it is faster to do it during voxelization
		vec3 ShadowWorldPosition = g_WorldPosition + u_F_PlayerPosition;
		float Shadow = ComputeDirectionalShadow(ShadowWorldPosition);
		float W = Shadow < 0.002f ? 0.5f : 1.0f;

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
		imageStore(o_VoxelVolume, StoreLoc, vec4(Color, W));
	}
}