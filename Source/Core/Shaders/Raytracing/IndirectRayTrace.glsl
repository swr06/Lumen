/*
Traces through voxelized scene using ray marching while utilizing distance fields 
SSGI is also implemented, it is used as a fallback when there isnt voxel data or when a pixel is outside 
the voxelization distance 
Finally, I have plans on making use of an octree, you can represent much larger scenes with it 
If not an octree, I might try having many cascades. 
Although, 256^3 is just terrible, I'm very much leaning towards the octrees, but lets see. 
*/

#version 450 core
#define PI 3.14159265359
#define MAX_VOXEL_DIST (WORLD_SIZE_X+1)
#define VOXEL_SIZE 1

// Bayer matrix, used for testing dithering
#define Bayer4(a)   (Bayer2(  0.5 * (a)) * 0.25 + Bayer2(a))
#define Bayer8(a)   (Bayer4(  0.5 * (a)) * 0.25 + Bayer2(a))
#define Bayer16(a)  (Bayer8(  0.5 * (a)) * 0.25 + Bayer2(a))
#define Bayer32(a)  (Bayer16( 0.5 * (a)) * 0.25 + Bayer2(a))
#define Bayer64(a)  (Bayer32( 0.5 * (a)) * 0.25 + Bayer2(a))
#define Bayer128(a) (Bayer64( 0.5 * (a)) * 0.25 + Bayer2(a))
#define Bayer256(a) (Bayer128(0.5 * (a)) * 0.25 + Bayer2(a))

layout (location = 0) out vec3 o_IndirectDiffuse;
layout (location = 1) out float o_VXAO;

in vec2 v_TexCoords;

uniform sampler2D u_AlbedoTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_DepthTexture;
uniform sampler2D u_ShadowTexture;
uniform sampler2D u_BlueNoise;
uniform samplerCube u_Skymap;
uniform sampler2D u_PreviousFrameLighting;

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

float Bayer2(vec2 a){
    a = floor(a);
    return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

// Function prototypes 
vec3 cosWeightedRandomHemisphereDirection(const vec3 n);
float VoxelTraversalDF(vec3 origin, vec3 direction, inout vec3 normal, inout vec4 VoxelData, in int dist);
vec3 WorldPosFromCoord(vec2 txc);
vec3 WorldPosFromDepth(float depth, vec2 txc);
bool voxel_traversal(vec3 origin, vec3 direction, inout vec4 block, out vec3 normal, out vec3 world_pos, int dist);
vec2 ScreenSpaceRayTrace(vec3 Normal, float Depth, vec2 TexCoords, bool ReducedSteps);
bool IsInScreenSpace(in vec3 p);
vec3 RayTraceSSRTRay(float Depth, vec3 Normal, bool ComputeSkyRadiance, bool ReducedSteps, bool DarkenSky);
vec2 ScreenSpaceRayTrace(vec3 WorldPosition, vec3 CosineDirection);

// 

float nextFloat(inout int seed);
float nextFloat(inout int seed, in float min, in float max);
float nextFloat(inout int seed, in float max);


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

float ComputeDirectionalShadow(vec3 WorldPosition) 
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
	return float(smoothfilter(u_ShadowTexture, ProjectionCoordinates.xy).x < ProjectionCoordinates.z - 0.01);
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
	const vec3 SUN_COLOR = vec3(6.90f); // ;)
	float shadow = a.w < 0.6f ? 0.0f : 1.0f;
	shadow = clamp(1.0f - shadow, 0.0f, 1.0f);
	return clamp(CalculateDirectionalLight(p, u_LightDirection, SUN_COLOR, pow(a.xyz, vec3(1.0f)), n, shadow), 0.0f, 5.0f);
}

// Calculates lambert diffuse radiance from skymap (can be used with any other environment map as well)
vec3 ComputeSkymapRadiance(int Samples, vec3 Normal)
{
	vec3 SkyRadiance = vec3(0.0f);

	for (int s = 0 ; s < Samples ; s++) {
		vec3 HemisphereDirection = cosWeightedRandomHemisphereDirection(Normal);	
		SkyRadiance += texture(u_Skymap, HemisphereDirection).xyz;
	}

	SkyRadiance /= float(Samples);
	return SkyRadiance*0.75;
}

// Gets the shading for a single ray 
vec3 GetBlockRayColor(in Ray r, out vec3 pos, inout vec3 out_n, inout float T, float BaseDepth, vec3 BaseNormal, int Bounce)
{
	const bool SSGI_FALLBACK = false;
	const bool SKYMAP_FALLBACK = false;
	vec4 data = vec4(0.0f);
	
	T = VoxelTraversalDF(r.Origin, r.Direction, out_n, data, MAX_VOXEL_DIST);
	bool Intersect = T > 0.0f;
	pos = r.Origin + (r.Direction * T);

	if (Intersect) 
	{ 
		return GetDirectLighting(pos, out_n, data) + (vec3(0.05, 0.05, 0.075f) * 0.4f);
	} 

	else {

		// Calculate SSGI if no intersection :

		if (Bounce == 0 && SSGI_FALLBACK) {
			return RayTraceSSRTRay(BaseDepth, BaseNormal, false, false, false).xyz * 2.0f; // /2 after the loop, *2 here to preserve energy
		} 

		if (SKYMAP_FALLBACK) {
			 return ComputeSkymapRadiance(4, BaseNormal);
		}

		return vec3(0.0f);
	}

	return vec3(0.0f);
}

vec4 CalculateDiffuse(in vec3 initial_origin, in vec3 input_normal, out vec3 dir, float BaseDepth, vec3 BaseNormal)
{
	const float bias = (sqrt(2.0f) * 1.0f) + (1e-2);
	Ray new_ray = Ray(initial_origin + input_normal * bias, cosWeightedRandomHemisphereDirection(input_normal));

	vec3 total_color = vec3(0.0f);;

	vec3 Position;
	vec3 Normal;
	const float MAX_VXAO_DIST = 3.5f;
	float AO = 0.0f;

	int bounces = 2;

	for (int i = 0 ; i < bounces ; i++)
	{
		vec3 tangent_normal;
		float T;
		total_color += GetBlockRayColor(new_ray, Position, Normal, T, BaseDepth, BaseNormal, i) * (1.0f / float(i + 1.0f));

		if (i == 0 && T > 0.0f && T < MAX_VXAO_DIST + 1e-2) {
			AO += pow(clamp(T / MAX_VOXEL_DIST, 0.0f, 1.0f), 1.0f);
		}

		if (T <= 0.0f) 
		{ 
			break;
		}

		new_ray.Origin = Position + Normal * bias;
		new_ray.Direction = cosWeightedRandomHemisphereDirection(Normal);
	}
	
	return vec4(total_color.xyz, AO);
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

void FixOutput() {
	if (isnan(o_IndirectDiffuse.x)||isnan(o_IndirectDiffuse.y)||isnan(o_IndirectDiffuse.z)) {
		o_IndirectDiffuse = vec3(0.0f);
	}
}

void main() 
{
	o_VXAO = 0.0f;

	HASH2SEED = (v_TexCoords.x * v_TexCoords.y) * 489.0 * 20.0f;
	HASH2SEED += fract(u_Time) * 100.0f;

	float Depth = texture(u_DepthTexture, v_TexCoords).x;
	vec3 RayDirection = normalize(GetRayDirectionAt(v_TexCoords));
	vec3 ActualWorldPosition = WorldPosFromDepth(Depth, v_TexCoords).xyz;
	vec3 Normal = texture(u_NormalTexture, v_TexCoords).xyz;

	if (Depth > 0.99999f) {
		o_IndirectDiffuse += vec3(0.0f);
		FixOutput();
		return;
	}

	vec3 MinAmbient = vec3(150.0f, 150.0f, 255.0f) / 255.0f;
	MinAmbient = MinAmbient * 0.01f;

	const bool DEBUG_SSGI = false;
	o_IndirectDiffuse = vec3(MinAmbient);

	if (DEBUG_SSGI) { 

		vec3 ScreenSpaceIndirectDiffuse = vec3(0.0f);
		ScreenSpaceIndirectDiffuse = RayTraceSSRTRay(Depth, Normal, false, false, false).xyz;
		o_IndirectDiffuse += ScreenSpaceIndirectDiffuse;
		FixOutput();
		return;

	}

	//// Convert to voxel space : 
	vec3 PositionDelta = u_ViewerPosition - u_VoxelizationPosition;
	vec3 VoxelPosition;
	VoxelPosition = (u_ViewerPosition / 256.0f) + vec3(128.0f, 128.0f, 128.0f);
	VoxelPosition = VoxelPosition + RayDirection * (distance(ActualWorldPosition, u_ViewerPosition) / 2.0f);
	
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
	vec3 VoxelPositionNormalized = VoxelPosition / 256.0f;
	if (VoxelPositionNormalized.x < 0.0f + 0.01f || VoxelPositionNormalized.x > 1.0f - 0.01f ||
		VoxelPositionNormalized.y < 0.0f + 0.01f || VoxelPositionNormalized.y > 1.0f - 0.01f ||
		VoxelPositionNormalized.z < 0.0f + 0.01f || VoxelPositionNormalized.z > 1.0f - 0.01f)
	{
		vec3 ScreenSpaceIndirectDiffuse = vec3(0.0f);
		ScreenSpaceIndirectDiffuse = RayTraceSSRTRay(Depth, Normal, false, false, false).xyz;
		o_IndirectDiffuse = MinAmbient*3.0f;
		o_IndirectDiffuse += ScreenSpaceIndirectDiffuse;
		return;
	}
	
	vec4 IndirectVXGIDiffuse = vec4(0.0f);
	vec3 SampleRayDirection;
	IndirectVXGIDiffuse = CalculateDiffuse(VoxelPosition.xyz, Normal.xyz, SampleRayDirection, Depth, Normal).xyzw;
	o_IndirectDiffuse += IndirectVXGIDiffuse.xyz;
	o_VXAO = IndirectVXGIDiffuse.w;
	FixOutput();
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

//////////////////////////////
// Screen space ray tracing //
/////////////////////////////

vec3 RayTraceSSRTRay(float Depth, vec3 Normal, bool ComputeSkyRadiance, bool ReducedSteps, bool DarkenSky) 
{
	vec2 UV = ScreenSpaceRayTrace(Normal, Depth, v_TexCoords, ReducedSteps);
	vec3 BounceRadiance = vec3(0.0f);
	float DepthAt_First = texture(u_DepthTexture, UV.xy).x;

	if (IsInScreenSpace(vec3(UV, 0.01f)) && DepthAt_First < 0.999995f)
	{
		// First Bounce : 
		// Compute lighting, without reusing previous frames, might be changed in the future 
		// to improve performance

		vec3 WorldPositionAt_First = WorldPosFromDepth(DepthAt_First, UV.xy);
		vec3 NormalAt_First = texture(u_NormalTexture, UV.xy).xyz;
		float Shadow_First = 1.0f-ComputeDirectionalShadow(WorldPositionAt_First);
		vec3 AlbedoAt_First = pow(texture(u_AlbedoTexture, UV.xy).xyz, vec3(1.0f/2.2f));
		BounceRadiance += clamp(CalculateDirectionalLight(WorldPositionAt_First, u_LightDirection, vec3(3.0f), AlbedoAt_First, NormalAt_First, Shadow_First), 0.0f, 5.0f);

		// Second Bounce
		// Ray trace from first hit point and first normal

		vec2 SecondBounceUV = ScreenSpaceRayTrace(NormalAt_First, DepthAt_First, UV, ReducedSteps);
		float DepthAt_Second = texture(u_DepthTexture, SecondBounceUV.xy).x;

		if (IsInScreenSpace(vec3(SecondBounceUV, 0.01f)) && DepthAt_Second < 0.999995f) 
		{
			// Compute lighting : 
			vec3 WorldPositionAt_Second = WorldPosFromDepth(DepthAt_Second, SecondBounceUV.xy);
			vec3 NormalAt_Second = texture(u_NormalTexture, SecondBounceUV.xy).xyz;
			float Shadow_Second = 1.0f-ComputeDirectionalShadow(WorldPositionAt_Second);
			vec3 AlbedoAt_Second = pow(texture(u_AlbedoTexture, SecondBounceUV.xy).xyz, vec3(1.0f/2.2f));
			BounceRadiance += clamp(CalculateDirectionalLight(WorldPositionAt_Second, u_LightDirection, vec3(3.0f), AlbedoAt_Second, NormalAt_Second, Shadow_Second), 0.0f, 5.0f);
		}
	}

	else {
		return vec3(0.0f);
		BounceRadiance = vec3(0.0f);
	
		if (ComputeSkyRadiance) {
			float m = DarkenSky ? 1.0f : 1.8250f;
			BounceRadiance = ComputeSkymapRadiance(12, Normal) * m;  // multiplying it because the result is then divided by 2
		}
	}

	BounceRadiance /= 2.0f;
	return BounceRadiance;
} 

vec3 ViewPosFromDepth(float depth, vec2 UV)
{
    float z = depth * 2.0f - 1.0f; // No need to linearize
    vec4 ClipSpacePosition = vec4(UV * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_InverseProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    return ViewSpacePosition.xyz;
}

vec3 ViewSpaceToClipSpace(in vec3 view_space)
{
	vec4 clipSpace = u_Projection * vec4(view_space, 1);
	vec3 NDCSpace = clipSpace.xyz / clipSpace.w;
	vec3 screenSpace = 0.5 * NDCSpace + 0.5;
	return screenSpace;
}

vec3 ViewSpaceToScreenSpace(vec3 ViewSpace) 
{
    vec4 ClipSpace = u_Projection * vec4(ViewSpace, 1.0);
    ClipSpace.xyz = ClipSpace.xyz / ClipSpace.w;
    return ClipSpace.xyz * 0.5f + 0.5f;
}

vec3 ScreenSpaceToWorldSpace(in vec2 txc)
{
    float d = texture(u_DepthTexture, txc).r;
    return ViewPosFromDepth(d, txc);
}

bool IsInScreenSpace(in vec3 p)
{
    if (p.x < 0.0f || p.x > 1.0f ||
		p.y < 0.0f || p.y > 1.0f ||
		p.z < 0.0f || p.z > 1.0f)
	{
		return false;
	}

    return true;
}


//vec2 ScreenSpaceRayTrace(vec3 Normal, float Depth, vec2 TexCoords, bool ReducedSteps)
//{
//    //vec3 ViewSpaceNormal = vec3(u_View * vec4(Normal, 0.0f));
//    //vec3 ViewSpaceViewDirection = normalize(ViewSpacePosition);
//	
//	const int MAX_REFINEMENTS = 5;
//
//	vec3 CosineDirection = cosWeightedRandomHemisphereDirection(Normal);
//    vec3 LambertDirection = vec3(u_View * vec4(CosineDirection, 0.0f));
//	LambertDirection = normalize(LambertDirection);
//
//	float InitialStepAmount = 1.0 - clamp(0.1f / 100.0, 0.0, 0.99);
//    vec3 ViewSpacePosition = ViewPosFromDepth(Depth, TexCoords);
//    vec3 ViewSpaceVector = InitialStepAmount * LambertDirection;
//	vec3 PreviousPosition = ViewSpacePosition;
//    vec3 ViewSpaceVectorPosition = PreviousPosition + ViewSpaceVector;
//    vec3 CurrentPosition = ViewSpaceToScreenSpace(ViewSpaceVectorPosition);
//
//	int NumRefinements = 0;
//	vec2 FinalUV = vec2(-1.0f);
//	float finalSampleDepth = 0.0;
//
//	int StepCount = 55 - (20 * int(ReducedSteps));
//
//    for (int i = 0; i < StepCount; i++)
//    {
//        if(-ViewSpaceVectorPosition.z > u_zFar * 1.4f || -ViewSpaceVectorPosition.z < 0.0f)
//        {
//		    break;
//		}
//
//        vec2 SamplePos = CurrentPosition.xy;
//        float SampleDepth = ScreenSpaceToWorldSpace(SamplePos).z;
//        float CurrentDepth = ViewSpaceVectorPosition.z;
//        float diff = SampleDepth - CurrentDepth;
//        float error = length(ViewSpaceVector / pow(2.0f, NumRefinements));
//
//        if(diff >= 0 && diff <= error * 2.0f && NumRefinements <= MAX_REFINEMENTS)
//        {
//        	ViewSpaceVectorPosition -= ViewSpaceVector / pow(2.0f, NumRefinements);
//        	NumRefinements++;
//		}
//
//		else if (diff >= 0 && diff <= error * 4.0f && NumRefinements > MAX_REFINEMENTS)
//		{
//			FinalUV = SamplePos;
//			finalSampleDepth = SampleDepth;
//			break;
//		}
//
//        ViewSpaceVectorPosition += ViewSpaceVector / pow(2.0f, NumRefinements);
//
//        if (i > 1)
//        {
//            ViewSpaceVector *= 1.375f; // increase the vector's length progressively 
//        }
//
//		CurrentPosition = ViewSpaceToScreenSpace(ViewSpaceVectorPosition);
//
//		if (!IsInScreenSpace(CurrentPosition)) 
//        {
//            break;
//        }
//    }
//
//    return FinalUV;
//}



vec2 ScreenSpaceRayTrace(vec3 Normal, float Depth, vec2 TexCoords, bool ReducedSteps)
{
	vec3 CosineDirection = cosWeightedRandomHemisphereDirection(Normal);
    vec3 LambertDirection = vec3(u_View * vec4(CosineDirection, 0.0f));
	LambertDirection = normalize(LambertDirection);
	float InitialStepAmount = 1.0 - clamp(0.1f / 100.0, 0.0, 0.99);
    vec3 ViewSpacePosition = WorldPosFromDepth(Depth, TexCoords) + Normal * 0.025f;
	ViewSpacePosition = vec3(u_View * vec4(ViewSpacePosition, 1.0f));
	vec3 ScreenSpacePosition = ViewSpaceToScreenSpace(ViewSpacePosition);
	int Steps = 50;
    vec3 ScreenSpaceDirection = normalize(ViewSpaceToScreenSpace(ViewSpacePosition + LambertDirection) - ScreenSpacePosition) * (1.25f / float(Steps));
    vec3 FinalPosition = vec3(0.0f);
    float Jitter = Bayer32(gl_FragCoord.xy);
    FinalPosition = ScreenSpacePosition + ScreenSpaceDirection * Jitter;

    for(int i = 0; i < Steps; i++) 
	{
        FinalPosition += ScreenSpaceDirection;

        if (IsInScreenSpace(vec3(FinalPosition.xy, 0.01f)) == false || FinalPosition.z > 0.999999f)
		{
			break;
		}

        float DepthAt = texture(u_DepthTexture, FinalPosition.xy).r;

        if(FinalPosition.z > DepthAt) 
		{
			for(int i = 0; i < 5; i++) 
			{
				float depth = texture(u_DepthTexture, FinalPosition.xy).r;
				float depthDelta = depth - FinalPosition.z;

				if(depthDelta > 0.0) 
				{ 
					FinalPosition += ScreenSpaceDirection;
				}

				else
				{	
					FinalPosition -= ScreenSpaceDirection;
				}

				if (FinalPosition.z > 0.999999f) { return vec2(-1.0f); }

				ScreenSpaceDirection *= 0.7f;
			}

			return FinalPosition.xy;
        }
    }

    return vec2(-1.0f);
}














///// 


vec2 ScreenSpaceRayTrace(vec3 WorldPosition, vec3 CosineDirection)
{
    //vec3 ViewSpaceNormal = vec3(u_View * vec4(Normal, 0.0f));
    //vec3 ViewSpaceViewDirection = normalize(ViewSpacePosition);
	
	const int MAX_REFINEMENTS = 4;
    vec3 LambertDirection = vec3(u_View * vec4(CosineDirection, 0.0f));
	LambertDirection = normalize(LambertDirection);

	float InitialStepAmount = 1.0 - clamp(0.1f / 100.0, 0.0, 0.99);
    vec3 ViewSpacePosition = vec3(u_View * vec4(WorldPosition, 1.0f));
    vec3 ViewSpaceVector = InitialStepAmount * LambertDirection;
	vec3 PreviousPosition = ViewSpacePosition;
    vec3 ViewSpaceVectorPosition = PreviousPosition + ViewSpaceVector;
    vec3 CurrentPosition = ViewSpaceToScreenSpace(ViewSpaceVectorPosition);

	int NumRefinements = 0;
	vec2 FinalUV = vec2(-1.0f);
	float finalSampleDepth = 0.0;

    for (int i = 0; i < 40; i++)
    {
        if(-ViewSpaceVectorPosition.z > u_zFar * 1.4f || -ViewSpaceVectorPosition.z < 0.0f)
        {
		    break;
		}

        vec2 SamplePos = CurrentPosition.xy;
        float SampleDepth = ScreenSpaceToWorldSpace(SamplePos).z;
        float CurrentDepth = ViewSpaceVectorPosition.z;
        float diff = SampleDepth - CurrentDepth;
        float error = length(ViewSpaceVector / pow(2.0f, NumRefinements));

        if(diff >= 0 && diff <= error * 2.0f && NumRefinements <= MAX_REFINEMENTS)
        {
        	ViewSpaceVectorPosition -= ViewSpaceVector / pow(2.0f, NumRefinements);
        	NumRefinements++;
		}

		else if (diff >= 0 && diff <= error * 4.0f && NumRefinements > MAX_REFINEMENTS)
		{
			FinalUV = SamplePos;
			finalSampleDepth = SampleDepth;
			break;
		}

        ViewSpaceVectorPosition += ViewSpaceVector / pow(2.0f, NumRefinements);

        if (i > 1)
        {
            ViewSpaceVector *= 1.375f; // increase the vector's length progressively 
        }

		CurrentPosition = ViewSpaceToScreenSpace(ViewSpaceVectorPosition);

		if (!IsInScreenSpace(CurrentPosition)) 
        {
            break;
        }
    }

    return FinalUV;
}

// Used for testing //

// Projects a ray to a cube, so that it always starts from some point that lies on the cube 
float ProjectToCube(vec3 ro, vec3 rd) 
{	
	const vec3 MapSize = vec3(WORLD_SIZE_X, WORLD_SIZE_Y, WORLD_SIZE_Z);
	float tx1 = (0 - ro.x) / rd.x;
	float tx2 = (MapSize.x - ro.x) / rd.x;

	float ty1 = (0 - ro.y) / rd.y;
	float ty2 = (MapSize.y - ro.y) / rd.y;

	float tz1 = (0 - ro.z) / rd.z;
	float tz2 = (MapSize.z - ro.z) / rd.z;

	float tx = max(min(tx1, tx2), 0);
	float ty = max(min(ty1, ty2), 0);
	float tz = max(min(tz1, tz2), 0);

	float t = max(tx, max(ty, tz));
	
	return t;
}


float voxel_traversal(vec3 orig, vec3 direction, inout vec3 normal, inout vec4 blockType, in int mdist) 
{
	const vec3 MapSize = vec3(WORLD_SIZE_X, WORLD_SIZE_Y, WORLD_SIZE_Z);

	vec3 origin = orig;
	const float epsilon = 0.001f;
	float t1 = max(ProjectToCube(origin, direction) - epsilon, 0.0f);
	origin += t1 * direction;

	int mapX = int(floor(origin.x));
	int mapY = int(floor(origin.y));
	int mapZ = int(floor(origin.z));

	float sideDistX;
	float sideDistY;
	float sideDistZ;

	float deltaDX = abs(1.0f / direction.x);
	float deltaDY = abs(1.0f / direction.y);
	float deltaDZ = abs(1.0f / direction.z);
	float T = -1.0;

	int stepX;
	int stepY;
	int stepZ;

	int hit = 0;
	int side;

	if (direction.x < 0)
	{
		stepX = -1;
		sideDistX = (origin.x - mapX) * deltaDX;
	} 
	
	else 
	{
		stepX = 1;
		sideDistX = (mapX + 1.0 - origin.x) * deltaDX;
	}

	if (direction.y < 0) 
	{
		stepY = -1;
		sideDistY = (origin.y - mapY) * deltaDY;
	} 
	
	else 
	{
		stepY = 1;
		sideDistY = (mapY + 1.0 - origin.y) * deltaDY;
	}

	if (direction.z < 0) 
	{
		stepZ = -1;
		sideDistZ = (origin.z - mapZ) * deltaDZ;
	} 
	
	else 
	{
		stepZ = 1;
		sideDistZ = (mapZ + 1.0 - origin.z) * deltaDZ;
	}

	for (int i = 0; i < mdist; i++) 
	{
		if ((mapX >= MapSize.x && stepX > 0) || (mapY >= MapSize.y && stepY > 0) || (mapZ >= MapSize.z && stepZ > 0)) break;
		if ((mapX < 0 && stepX < 0) || (mapY < 0 && stepY < 0) || (mapZ < 0 && stepZ < 0)) break;

		if (sideDistX < sideDistY && sideDistX < sideDistZ) 
		{
			sideDistX += deltaDX;
			mapX += stepX;
			side = 0;
		} 
		
		else if (sideDistY < sideDistX && sideDistY < sideDistZ)
		{
			sideDistY += deltaDY;
			mapY += stepY;
			side = 1;
		} 
		
		else 
		{
			sideDistZ += deltaDZ;
			mapZ += stepZ;
			side = 2;
		}

		vec4 block = GetVoxel(ivec3(mapX, mapY, mapZ));

		if (block.w != 0) 
		{
			hit = 1;
			blockType = block;

			if (side == 0) 
			{
				T = (mapX - origin.x + (1 - stepX) / 2) / direction.x + t1;
				normal = vec3(1, 0, 0) * -stepX;
			}

			else if (side == 1) 
			{
				T = (mapY - origin.y + (1 - stepY) / 2) / direction.y + t1;
				normal = vec3(0, 1, 0) * -stepY;
			}

			else
			{
				T = (mapZ - origin.z + (1 - stepZ) / 2) / direction.z + t1;
				normal = vec3(0, 0, 1) * -stepZ;
			}

			break;
		}
	}

	return T;
}

//

// RNG 

//

const int MIN = -2147483648;
const int MAX = 2147483647;

int xorshift(in int value) 
{
    // Xorshift*32
    // Based on George Marsaglia's work: http://www.jstatsoft.org/v08/i14/paper
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
}

int nextInt(inout int seed) 
{
    seed = xorshift(seed);
    return seed;
}

float nextFloat(inout int seed) 
{
    seed = xorshift(seed);
    // FIXME: This should have been a seed mapped from MIN..MAX to 0..1 instead
    return abs(fract(float(seed) / 3141.592653));
}

float nextFloat(inout int seed, in float max) 
{
    return nextFloat(seed) * max;
}

float nextFloat(inout int seed, in float min, in float max) 
{
    return min + (max - min) * nextFloat(seed);
}

// end.