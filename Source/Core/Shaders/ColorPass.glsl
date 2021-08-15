#version 400 core
#define PI 3.14159265359

layout (location = 0) out vec3 o_Color;

in vec2 v_TexCoords;

uniform sampler2D u_AlbedoTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_PBRTexture;
uniform sampler2D u_DepthTexture;

uniform vec3 u_ViewerPosition;
uniform vec3 u_LightDirection;
uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;
uniform mat4 u_Projection;
uniform mat4 u_View;

const vec3 SUN_COLOR = vec3(50.5f);

vec3 CalculateDirectionalLight(vec3 world_pos, vec3 light_dir, vec3 radiance, vec3 albedo, vec3 normal, vec2 rm, float shadow);

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

void main() 
{
	vec3 WorldPosition = WorldPosFromCoord(v_TexCoords);
	vec3 Normal = texture(u_NormalTexture, v_TexCoords).xyz;
	vec3 Albedo = texture(u_AlbedoTexture, v_TexCoords).xyz;
	vec2 RoughnessMetalness = texture(u_PBRTexture, v_TexCoords).xy;
	vec3 NormalizedSunDir = normalize(u_LightDirection);
	o_Color = CalculateDirectionalLight(WorldPosition, NormalizedSunDir, SUN_COLOR, Albedo, Normal, RoughnessMetalness.xy, 0.0f);
}

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

vec3 CalculateDirectionalLight(vec3 world_pos, vec3 light_dir, vec3 radiance, vec3 albedo, vec3 normal, vec2 rm, float shadow)
{
	vec3 radiance_s = radiance;
    const float Epsilon = 0.00001;
    float Shadow = min(shadow, 1.0f);

    vec3 Lo = normalize(u_ViewerPosition - world_pos);

	vec3 N = normal;
	float cosLo = max(0.0, dot(N, Lo));
	vec3 Lr = 2.0 * cosLo * N - Lo;
	vec3 F0 = mix(vec3(0.04), albedo, rm.g);

    vec3 Li = light_dir;
	vec3 Lradiance = radiance;

	vec3 Lh = normalize(Li + Lo);

	float cosLi = max(0.0, dot(N, Li));
	float cosLh = max(0.0, dot(N, Lh));
	
	vec3 F = fresnelroughness(Lo, normal.xyz, vec3(F0), rm.r); // use fresnel roughness, gives a slightly better approximation
	float D = ndfGGX(cosLh, rm.r);
	float G = gaSchlickGGX(cosLi, cosLo, rm.r);

	vec3 kd = mix(vec3(1.0) - F, vec3(0.0), rm.g);
	vec3 diffuseBRDF = kd * albedo;

	vec3 specularBRDF = (F * D * G) / max(Epsilon, 4.0 * cosLi * cosLo); 
	vec3 Result = (diffuseBRDF * Lradiance * cosLi) + (specularBRDF * radiance_s * cosLi);
    return Result;
}