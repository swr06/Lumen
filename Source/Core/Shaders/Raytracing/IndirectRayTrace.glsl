#version 450 core
#define PI 3.14159265359
#define MAX_VOXEL_DIST (WORLD_SIZE_X+4)
#define VOXEL_SIZE 1

layout (location = 0) out vec3 o_IndirectDiffuse;
layout (location = 1) out float o_VXAO;

in vec2 v_TexCoords;

uniform sampler2D u_AlbedoTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_DepthTexture;
uniform sampler2D u_ShadowTexture;
uniform sampler2D u_BlueNoise;
uniform samplerCube u_Skymap;

uniform sampler3D u_VoxelVolume;
uniform sampler3D u_VoxelDFVolume;

uniform vec3 u_VoxelizationPosition;

uniform vec3 u_ViewerPosition;
uniform vec3 u_LightDirection;
uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;
uniform mat4 u_Projection;
uniform mat4 u_View;
uniform mat4 u_LightVP;

uniform float u_Time;
uniform int WORLD_SIZE_X;
uniform int WORLD_SIZE_Y;
uniform int WORLD_SIZE_Z;

uniform float u_zNear;
uniform float u_zFar;

// Utility : 

float HASH2SEED = 0.0f;

struct Ray
{
	vec3 Origin;
	vec3 Direction;
};


// Function prototypes 
vec3 cosWeightedRandomHemisphereDirection(const vec3 n);
float VoxelTraversalDF(vec3 origin, vec3 direction, inout vec3 normal, inout vec4 VoxelData, in int dist);
vec3 WorldPosFromCoord(vec2 txc);
vec3 WorldPosFromDepth(float depth, vec2 txc);
bool voxel_traversal(vec3 origin, vec3 direction, inout vec4 block, out vec3 normal, out vec3 world_pos, int dist);

// Returns sample from skymap 
vec3 GetSkyColorAt(vec3 rd) 
{
	rd.y = clamp(rd.y, 0.125f, 1.5f);
    return texture(u_Skymap, (rd)).rgb;
}

// iq
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

float ComputeDirectionalShadow(vec3 WorldPosition, vec3 N) 
{
	vec4 ProjectionCoordinates = u_LightVP * vec4(WorldPosition, 1.0f);
	ProjectionCoordinates.xyz = ProjectionCoordinates.xyz / ProjectionCoordinates.w; // Perspective division is not really needed for orthagonal projection but whatever
    ProjectionCoordinates.xyz = ProjectionCoordinates.xyz * 0.5f + 0.5f;
	float shadow = 0.0;

	if (ProjectionCoordinates.z > 1.0)
	{
		return 0.0f;
	}

    float Depth = ProjectionCoordinates.z;
	return float(smoothfilter(u_ShadowTexture, ProjectionCoordinates.xy).x < ProjectionCoordinates.z - 0.1);
}

// Simplified BRDF
vec3 CalculateDirectionalLight(in vec3 world_pos, in vec3 light_dir, vec3 radiance, in vec3 albedo, in vec3 normal, in float shadow)
{
	vec3 DiffuseBRDF = albedo * max(dot(normal, normalize(-light_dir)), 0.0f) * (radiance * 1.5f);
    return DiffuseBRDF * shadow;
} 

// Returns direct lighting for a single point : 
vec3 GetDirectLighting(vec3 p, vec3 n, vec4 a) 
{
	const vec3 SUN_COLOR = vec3(2.0f);
	float shadow = a.w < 0.6f ? 0.0f : 1.0f;
	shadow = clamp(1.0f - shadow, 0.0f, 1.0f);
	return clamp(CalculateDirectionalLight(p, u_LightDirection, SUN_COLOR, pow(a.xyz, vec3(1.0f)), n, shadow), 0.0f, 5.0f);
}

// Gets the shading for a single ray 
vec3 GetBlockRayColor(in Ray r, out vec3 pos, out vec3 out_n)
{
	vec4 data = vec4(0.0f);
	
	float T = VoxelTraversalDF(r.Origin, r.Direction, out_n, data, MAX_VOXEL_DIST);
	bool Intersect = T > 0.0f;
	pos = r.Origin + (r.Direction * T);

	if (Intersect) 
	{ 
		return GetDirectLighting(pos, out_n, data);
	} 

	else 
	{	
		return GetSkyColorAt(r.Direction);
	}
}

vec4 CalculateDiffuse(in vec3 initial_origin, in vec3 input_normal, out vec3 dir)
{
	const float bias = sqrt(2.0f) * 1.0f;
	Ray new_ray = Ray(initial_origin + input_normal * bias, cosWeightedRandomHemisphereDirection(input_normal));

	vec3 total_color = vec3(0.0f);;

	vec3 Position;
	vec3 Normal;
	float ao = 1.0f;

	for (int i = 0 ; i < 2 ; i++)
	{
		vec3 tangent_normal;
		total_color += GetBlockRayColor(new_ray, Position, Normal);
		float T = distance(initial_origin, Position);
		new_ray.Origin = Position + Normal * bias;
		new_ray.Direction = cosWeightedRandomHemisphereDirection(Normal);
	}
	
	return vec4(total_color / 2.0f, ao); 
}

vec3 GetRayDirectionAt(vec2 screenspace)
{
	vec4 clip = vec4(screenspace * 2.0f - 1.0f, -1.0, 1.0);
	vec4 eye = vec4(vec2(u_InverseProjection * clip), -1.0, 0.0);
	return vec3(u_InverseView * eye);
}

float linearizeDepth(float depth)
{
	return (2.0 * u_zNear) / (u_zFar + u_zNear - depth * (u_zFar - u_zNear));
}

void main() 
{
	HASH2SEED = (v_TexCoords.x * v_TexCoords.y) * 489.0 * 20.0f;
	HASH2SEED += fract(u_Time) * 100.0f;

	float Depth = texture(u_DepthTexture, v_TexCoords).x;
	vec3 RayDirection = normalize(GetRayDirectionAt(v_TexCoords));
	
	// Convert to voxel space : 
	vec3 PositionDelta = u_ViewerPosition - u_VoxelizationPosition;
	vec3 VoxelPosition;
	vec3 ActualWorldPosition = WorldPosFromDepth(Depth, v_TexCoords).xyz;
	VoxelPosition = (u_ViewerPosition / 256.0f) + vec3(128.0f, 128.0f, 128.0f);
	VoxelPosition = VoxelPosition + RayDirection * (distance(ActualWorldPosition, u_ViewerPosition) / 2.0f);

	vec3 Normal = texture(u_NormalTexture, v_TexCoords).xyz;
	vec3 DominantAxis = vec3(0.0f);
	vec3 AbsoluteNormal = abs(Normal);

	if(AbsoluteNormal.z > AbsoluteNormal.x && AbsoluteNormal.z > AbsoluteNormal.y)
	{
		DominantAxis = vec3(0.0f, 0.0f, 1.0f) * sign(Normal.z);
	}
	
	else if (AbsoluteNormal.x > AbsoluteNormal.y && AbsoluteNormal.x > AbsoluteNormal.z)
	{
		DominantAxis = vec3(1.0f, 0.0f, 0.0f) * sign(Normal.x);
	} 
	
	else 
	{
		DominantAxis = vec3(0.0f, 1.0f, 0.0f) * sign(Normal.y);
	}


	ivec3 VoxelVolumeSize = ivec3(textureSize(u_VoxelVolume, 0));
	
	if (Depth > 0.99999f) {
		o_IndirectDiffuse = texture(u_Skymap, normalize(vec3(0.5))).xyz;
		return;
	}
	
	if (VoxelPosition.x >= float(VoxelVolumeSize.x / float(VOXEL_SIZE)) &&
		VoxelPosition.y >= float(VoxelVolumeSize.y / float(VOXEL_SIZE)) &&
		VoxelPosition.z >= float(VoxelVolumeSize.z / float(VOXEL_SIZE)))
	{
		o_IndirectDiffuse = texture(u_Skymap, normalize(vec3(0.5))).xyz;
		return;
	}
	
	vec3 IndirectDiffuse = vec3(0.0f);
	const int SPP = 1;
	vec4 AccumulatedDiffuse = vec4(0.0f);
	
	for (int s = 0 ; s < SPP ; s++) 
	{
		vec3 RayDirection;
		AccumulatedDiffuse += CalculateDiffuse(VoxelPosition.xyz, Normal.xyz, RayDirection);
	}
	
	IndirectDiffuse.xyz = AccumulatedDiffuse.xyz / float(SPP);
	o_IndirectDiffuse = IndirectDiffuse;
	o_VXAO = AccumulatedDiffuse.w / float(SPP);
}

vec2 hash2() 
{
	return fract(sin(vec2(HASH2SEED += 0.1, HASH2SEED += 0.1)) * vec2(43758.5453123, 22578.1459123));
}

vec3 cosWeightedRandomHemisphereDirection(const vec3 n) 
{
  	vec2 r = vec2(hash2());
	//vec2 r = vec2(nextFloat(RNG_SEED), nextFloat(RNG_SEED));
    //vec2 r = SampleBlueNoise2D();

	float PI2 = 2.0f * PI;
	vec3  uu = normalize(cross(n, vec3(0.0,1.0,1.0)));
	vec3  vv = cross(uu, n);
	float ra = sqrt(r.y);
	float rx = ra * cos(PI2 * r.x); 
	float ry = ra * sin(PI2 * r.x);
	float rz = sqrt(1.0 - r.y);
	vec3  rr = vec3(rx * uu + ry * vv + rz * n );
    
    return normalize(rr);
}

vec3 WorldPosFromCoord(vec2 txc)
{
	float depth = texture(u_DepthTexture, txc).r;
    float z = depth * 2.0 - 1.0;
    vec4 ClipSpacePosition = vec4(txc * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_InverseProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    vec4 WorldPos = u_InverseView * ViewSpacePosition;
    return WorldPos.xyz;
}

vec3 WorldPosFromDepth(float depth, vec2 txc)
{
    float z = depth * 2.0 - 1.0;
    vec4 ClipSpacePosition = vec4(txc * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_InverseProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    vec4 WorldPos = u_InverseView * ViewSpacePosition;
    return WorldPos.xyz;
}


// -- Intersection methods -- 





bool IsInVolume(in vec3 pos)
{
    if (pos.x < 0.0f || pos.y < 0.0f || pos.z < 0.0f || 
        pos.x > float(WORLD_SIZE_X - 1) || pos.y > float(WORLD_SIZE_Y - 1) || pos.z > float(WORLD_SIZE_Z - 1))
    {
        return false;    
    }   

    return true;
}

vec4 GetVoxel(ivec3 loc)
{
    if (IsInVolume(loc))
    {
        return texelFetch(u_VoxelVolume, loc, 0).rgba;
    }
    
    return vec4(0.0f);
}

float ToConservativeEuclidean(float Manhattan)
{
	return Manhattan == 1 ? 1 : Manhattan * 0.57735026918f;
}

float GetDistance(ivec3 loc)
{
    if (IsInVolume(loc))
    {
         return (texelFetch(u_VoxelDFVolume, loc, 0).r);
    }
    
    return -1.0f;
}

bool VoxelExists(in vec3 loc)
{
    if (GetVoxel(ivec3(loc)).w > 0.001f) 
    {
        return true;
    }

    return false;
}

float GetManhattanDist(vec3 p1, vec3 p2)
{
	float Manhattan = abs(p1.x - p2.x) + abs(p1.y - p2.y) + abs(p1.z - p2.z);
	return Manhattan;
}

float VoxelTraversalDF(vec3 origin, vec3 direction, inout vec3 normal, inout vec4 VoxelData, in int dist) 
{
	vec3 initial_origin = origin;
	const float epsilon = 0.01f;
	bool Intersection = false;

	int MinIdx = 0;
	ivec3 RaySign = ivec3(sign(direction));

	int itr = 0;

	for (itr = 0 ; itr < dist ; itr++)
	{
		ivec3 Loc = ivec3(floor(origin));
		
		if (!IsInVolume(Loc))
		{
			Intersection = false;
			break;
		}

		float Dist = GetDistance(Loc) * 255.0f; 

		int Euclidean = int(floor(ToConservativeEuclidean(Dist)));

		if (Euclidean == 0)
		{
			break;
		}

		if (Euclidean == 1)
		{
			// Do the DDA algorithm for one voxel 

			ivec3 GridCoords = ivec3(origin);
			vec3 WithinVoxelCoords = origin - GridCoords;
			vec3 DistanceFactor = (((1 + RaySign) >> 1) - WithinVoxelCoords) * (1.0f / direction);

			MinIdx = DistanceFactor.x < DistanceFactor.y && RaySign.x != 0
				? (DistanceFactor.x < DistanceFactor.z || RaySign.z == 0 ? 0 : 2)
				: (DistanceFactor.y < DistanceFactor.z || RaySign.z == 0 ? 1 : 2);

			GridCoords[MinIdx] += RaySign[MinIdx];
			WithinVoxelCoords += direction * DistanceFactor[MinIdx];
			WithinVoxelCoords[MinIdx] = 1 - ((1 + RaySign) >> 1) [MinIdx]; // Bit shifts (on ints) to avoid division

			origin = GridCoords + WithinVoxelCoords;
			origin[MinIdx] += RaySign[MinIdx] * 0.0001f;

			Intersection = true;
		}

		else 
		{
			origin += int(Euclidean - 1) * direction;
		}
	}

	if (Intersection)
	{
		normal = vec3(0.0f);
		normal[MinIdx] = -RaySign[MinIdx];
		VoxelData = GetVoxel(ivec3(floor(origin)));
		return VoxelData.w > 0.0f ? distance(origin, initial_origin) : -1.0f;
	}

	return -1.0f;
}

