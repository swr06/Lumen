#version 400 core
#define PI 3.14159265359

layout (location = 0) out vec3 o_Color;

in vec2 v_TexCoords;

uniform sampler2D u_AlbedoTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_PBRTexture;
uniform sampler2D u_DepthTexture;
uniform sampler2D u_ShadowTexture;
uniform sampler2D u_BlueNoise;
uniform sampler2D u_IndirectDiffuse;
uniform sampler2D u_VXAO;
uniform samplerCube u_Skymap;
uniform sampler2D u_NormalRaw;

uniform vec3 u_ViewerPosition;
uniform vec3 u_LightDirection;
uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;
uniform mat4 u_Projection;
uniform mat4 u_View;
uniform mat4 u_LightVP;

uniform vec2 u_Dims;

const vec3 SUN_COLOR = vec3(6.9f, 6.9f, 10.0f);

const vec2 PoissonDisk[32] = vec2[]
(
    vec2(-0.613392, 0.617481),  vec2(0.751946, 0.453352),
    vec2(0.170019, -0.040254),  vec2(0.078707, -0.715323),
    vec2(-0.299417, 0.791925),  vec2(-0.075838, -0.529344),
    vec2(0.645680, 0.493210),   vec2(0.724479, -0.580798),
    vec2(-0.651784, 0.717887),  vec2(0.222999, -0.215125),
    vec2(0.421003, 0.027070),   vec2(-0.467574, -0.405438),
    vec2(-0.817194, -0.271096), vec2(-0.248268, -0.814753),
    vec2(-0.705374, -0.668203), vec2(0.354411, -0.887570),
    vec2(0.977050, -0.108615),  vec2(0.175817, 0.382366),
    vec2(0.063326, 0.142369),   vec2(0.487472, -0.063082),
    vec2(0.203528, 0.214331),   vec2(-0.084078, 0.898312),
    vec2(-0.667531, 0.326090),  vec2(0.488876, -0.783441),
    vec2(-0.098422, -0.295755), vec2(0.470016, 0.217933),
    vec2(-0.885922, 0.215369),  vec2(-0.696890, -0.549791),
    vec2(0.566637, 0.605213),   vec2(-0.149693, 0.605762),
    vec2(0.039766, -0.396100),  vec2(0.034211, 0.979980)
);

vec3 CalculateDirectionalLight(vec3 world_pos, vec3 light_dir, vec3 radiance, vec3 albedo, vec3 normal, vec2 rm, float shadow);
float CalculateSunShadow(vec3 WorldPosition, vec3 N);

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

vec3 GetRayDirectionAt(vec2 screenspace)
{
	vec4 clip = vec4(screenspace * 2.0f - 1.0f, -1.0, 1.0);
	vec4 eye = vec4(vec2(u_InverseProjection * clip), -1.0, 0.0);
	return vec3(u_InverseView * eye);
}


const ivec4[7] xOffsets = ivec4[7](
	ivec4(-1, 0, 0, 1),
	ivec4( 0, 1,-1,-1),
	ivec4( 2, 0,-2,-1),
	ivec4( 2,-2, 2,-2),
	ivec4(-2,-2, 1, 1),
	ivec4( 0, 2,-1, 1),
	ivec4(69,69, 0,69)
);

const ivec4[7] yOffsets = ivec4[7]
(
	ivec4( 2,-1, 1, 0),
	ivec4( 0, 1, 0, 1),
	ivec4( 1, 2, 2,-1),
	ivec4(-1, 1, 2, 0),
	ivec4(-1,-2,-1, 2),
	ivec4(-2,-2,-2,-2),
	ivec4(69,69, 0,69)
);

float linearizeDepth(float depth)
{
	float ZNear = 0.1f;
	float ZFar = 1000.0f;
	return (2.0 * ZNear) / (ZFar + ZNear - depth * (ZFar - ZNear));
}

// Kernels :
const float[5] kernel = float[5] (0.00135,0.157305,0.68269,0.157305,0.00135);
const float[7] ker7 = float[7](0.000015,0.006194,0.196119,0.595343,0.196119,0.006194,0.000015);
const float[9] ker9 = float[9] (0.02853226260337099, 0.06723453549491201, 0.1240093299792275, 0.1790438646174162, 0.2023600146101466, 0.1790438646174162, 0.1240093299792275, 0.06723453549491201, 0.02853226260337099);
const float[13] ker13 = float[13](0.036262,0.051046,0.067526,0.083942,0.098059,	0.107644,0.111043,0.107644,0.098059,0.083942,0.067526,0.051046,0.036262);

/*
vec3 SpatialUpscale(sampler2D UpscaleTexture, vec3 BaseNormal, float BaseLinearDepth)
{
	ivec2 TileCoord = ivec2(gl_FragCoord.xy) % 2;
	int DitherSet = TileCoord.x + 2 * TileCoord.y;
	vec2 TexelSize = 1.0f / textureSize(UpscaleTexture, 0);
	vec3 TotalSample = vec3(0.0f);
	float TotalWeight = 0.0f;

	for(int i = 0; i < 7; i++) 
	{
		int x = xOffsets[i][DitherSet];
		int y = yOffsets[i][DitherSet];
		if(ivec2(x,y) == ivec2(69, 69)) continue;

		vec2 SampleCoord = v_TexCoords + vec2(x,y) * TexelSize;
		float NonLinearDepthAt = texture(u_DepthTexture, SampleCoord).x;
		float LinearDepthAt = linearizeDepth(NonLinearDepthAt);

		vec3 NormalAt = texture(u_NormalTexture, v_TexCoords).xyz;
		//float DepthWeight = exp(-abs(BaseLinearDepth - LinearDepthAt));
		float DepthWeight = 1.0f / abs(BaseLinearDepth - LinearDepthAt);
		float NormalWeight = max(dot(BaseNormal, NormalAt), 0.0f);
		//DepthWeight = pow(DepthWeight, 32.0f);
		NormalWeight = pow(NormalWeight, 128.0f);
		
		float BaseWeight = ker9[x + 4] * ker9[y + 4];
		BaseWeight = BaseWeight * clamp(DepthWeight * NormalWeight, 1e-6, 1.5f + 1e-4);
		BaseWeight = DepthWeight * NormalWeight;;
		BaseWeight += 0.02f;

		vec3 SampleAt = texture(UpscaleTexture, SampleCoord).xyz;
		TotalSample += SampleAt * BaseWeight;
		TotalWeight += BaseWeight;
	}

	TotalSample /= TotalWeight;
	return TotalSample;
}*/

vec3 SpatialUpscale(sampler2D UpscaleTexture, vec3 BaseNormal, float BaseLinearDepth)
{
	vec3 TotalSample = vec3(0.0f);
	float TotalWeight = 0.0f;

	vec2 TexelSize = 1.0f / textureSize(UpscaleTexture, 0);
	const float AtrousWeights[5] = float[5] (0.0625, 0.25, 0.375, 0.25, 0.0625);

	for (int x = -2 ; x <= 2 ; x++) {
		for (int y = -2 ; y <= 2 ; y++) {
			
			vec2 SampleCoord = v_TexCoords + vec2(x,y) * TexelSize;
			float LinearDepthAt = linearizeDepth(texture(u_DepthTexture, SampleCoord).x);
			vec3 NormalAt = texture(u_NormalRaw, SampleCoord.xy).xyz;

			float DepthWeight = 1.0f / (abs(LinearDepthAt - BaseLinearDepth) + 0.001f);
			DepthWeight = pow(DepthWeight, 12.0f);

			float NormalWeight = pow(abs(dot(NormalAt, BaseNormal)), 8.0f);

			float Kernel = AtrousWeights[x + 2] * AtrousWeights[y + 2];
			float Weight = Kernel * NormalWeight * DepthWeight;
			Weight = max(Weight, 0.01f);
			TotalSample += texture(UpscaleTexture, SampleCoord).xyz * Weight;
			TotalWeight += Weight;
		}
	}

	return TotalSample / TotalWeight;
}

void main() 
{	
	float depth = texture(u_DepthTexture, v_TexCoords).r;
	vec3 rD = GetRayDirectionAt(v_TexCoords).xyz;

	if (depth > 0.99995f) {
		vec3 Sample = texture(u_Skymap, normalize(rD)).xyz;
		o_Color = Sample*Sample;
		return;
	}

	float LinearDepth = linearizeDepth(depth);

	// Samples : 
	vec3 WorldPosition = WorldPosFromDepth(depth,v_TexCoords);
	vec3 Normal = texture(u_NormalTexture, v_TexCoords).xyz;
	vec3 NormalRaw = texture(u_NormalRaw, v_TexCoords).xyz;
	vec3 Albedo = texture(u_AlbedoTexture, v_TexCoords).xyz;
	vec2 RoughnessMetalness = texture(u_PBRTexture, v_TexCoords).xy;
	
	// Direct :
	vec3 NormalizedSunDir = normalize(u_LightDirection);
	float DirectionalShadow = CalculateSunShadow(WorldPosition, Normal);
	vec3 DirectLighting = CalculateDirectionalLight(WorldPosition, normalize(u_LightDirection), SUN_COLOR, Albedo, Normal, RoughnessMetalness, DirectionalShadow).xyz;
	
	// Indirect :
	//vec3 IndirectDiffuse = texture(u_IndirectDiffuse, v_TexCoords).xyz;
	vec3 IndirectDiffuse = SpatialUpscale(u_IndirectDiffuse, Normal, LinearDepth);

	// VXAO 
	float VXAO = 1.0f - texture(u_VXAO, v_TexCoords).r;
	VXAO = VXAO * VXAO;

	// Combine 
	vec3 AmbientTerm = ((IndirectDiffuse) * Albedo);
	o_Color = DirectLighting + AmbientTerm;
	
	// Temp :


	//o_Color = IndirectDiffuse;
	//o_Color = pow(IndirectDiffuse, vec3(3.0f)) * 0.05f ;
	//o_Color = pow(IndirectDiffuse / 500.0f, vec3(2.2f));
}

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

float CalculateSunShadow(vec3 WorldPosition, vec3 N)
{
	vec4 ProjectionCoordinates = u_LightVP * vec4(WorldPosition, 1.0f);
	ProjectionCoordinates.xyz = ProjectionCoordinates.xyz / ProjectionCoordinates.w; // Perspective division is not really needed for orthagonal projection but whatever
    ProjectionCoordinates.xyz = ProjectionCoordinates.xyz * 0.5f + 0.5f;
	float shadow = 0.0;

	if (ProjectionCoordinates.z > 1.0)
	{
		return 0.0f;
	}

    float ClosestDepth = texture(u_ShadowTexture, ProjectionCoordinates.xy).r; 
    float Depth = ProjectionCoordinates.z;
	float Bias = max(0.00025f * (1.0f - dot(N, u_LightDirection)), 0.0005f);  
	vec2 TexelSize = 1.0 / textureSize(u_ShadowTexture, 0);
	float noise = texture(u_BlueNoise, v_TexCoords * (u_Dims / textureSize(u_BlueNoise, 0).xy)).r;
	float scale = 1.0f;
	float scale_multiplier = 1.0f+(1.0f/24.0f);

	for(int x = 0; x <= 32; x++)
	{
		float theta = noise * (2.0f*PI);
		float cosTheta = cos(theta);
		float sinTheta = sin(theta);
		mat2 dither = mat2(vec2(cosTheta, -sinTheta), vec2(sinTheta, cosTheta));
		vec2 jitter_value;
		jitter_value = PoissonDisk[x] * dither;
		float pcf = smoothfilter(u_ShadowTexture, ProjectionCoordinates.xy + (jitter_value * scale * TexelSize)).r;  // force hardware bilinear
		shadow += ProjectionCoordinates.z - Bias > pcf ? 1.0f : 0.0f;    
		scale *= scale_multiplier;
	}

	shadow /= 32.0;
    return shadow;
}

// -- // 

float ndfGGX(float cosLh, float roughness)
{
	float alpha   = roughness * roughness;
	float alphaSq = alpha * alpha;

	float denom = (cosLh * cosLh) * (alphaSq - 1.0) + 1.0;
	return alphaSq / (PI * denom * denom);
}

float gaSchlickG1(float cosTheta, float k)
{
	return cosTheta / (cosTheta * (1.0 - k) + k);
}

float gaSchlickGGX(float cosLi, float cosLo, float roughness)
{
	float r = roughness + 1.0;
	float k = (r * r) / 8.0; // Epic suggests using this roughness remapping for analytic lights.
	return gaSchlickG1(cosLi, k) * gaSchlickG1(cosLo, k);
}

vec3 fresnelSchlick(vec3 F0, float cosTheta)
{
	return F0 + (vec3(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}


vec3 fresnelroughness(vec3 Eye, vec3 norm, vec3 F0, float roughness) 
{
	return F0 + (max(vec3(pow(1.0f - roughness, 3.0f)) - F0, vec3(0.0f))) * pow(max(1.0 - clamp(dot(Eye, norm), 0.0f, 1.0f), 0.0f), 5.0f);
}

vec3 CalculateDirectionalLight(vec3 world_pos, vec3 light_dir, vec3 radiance, vec3 albedo, vec3 N, vec2 rm, float shadow)
{
    const float Epsilon = 0.00001;
    vec3 Lo = normalize(u_ViewerPosition - world_pos);
	vec3 Li = -light_dir;
	vec3 Lradiance = radiance;
	vec3 Lh = normalize(Li + Lo);
	float cosLo = max(0.0, dot(N, Lo));
	float cosLi = max(0.0, dot(N, Li));
	float cosLh = max(0.0, dot(N, Lh));
	float roughness = rm.x;
	float metalness = rm.y;
	vec3 F0 = mix(vec3(0.04), albedo, metalness);
	vec3 F  = fresnelSchlick(F0, max(0.0, dot(Lh, Lo)));
	float D = ndfGGX(cosLh, roughness);
	float G = gaSchlickGGX(cosLi, cosLo, roughness);
	vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metalness);
	vec3 diffuseBRDF = kd * albedo;
	vec3 specularBRDF = (F * D * G) / max(Epsilon, 4.0 * cosLi * cosLo);
	vec3 final = (diffuseBRDF + specularBRDF) * Lradiance * cosLi;
	return final * (1.0f-shadow);
}