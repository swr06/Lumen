#version 330 core

layout (location = 0) out vec3 o_Lighting;
layout (location = 1) out vec3 o_Utility;
layout (location = 2) out float o_AO;

in vec2 v_TexCoords;

uniform sampler2D u_CurrentDepthTexture;
uniform sampler2D u_PreviousDepthTexture;

uniform sampler2D u_CurrentLighting;
uniform sampler2D u_PreviousLighting;

uniform sampler2D u_CurrentNormalTexture;
uniform sampler2D u_PreviousNormalTexture;

uniform sampler2D u_PreviousUtility;
uniform sampler2D u_CurrentAO;
uniform sampler2D u_PreviousAO;

uniform mat4 u_Projection;
uniform mat4 u_View;
uniform mat4 u_PrevProjection;
uniform mat4 u_PrevView;
uniform mat4 u_PrevInverseProjection;
uniform mat4 u_PrevInverseView;
uniform mat4 u_InverseProjection;
uniform mat4 u_InverseView;

vec3 WorldPosFromDepth(float depth, vec2 txc)
{
    float z = depth * 2.0 - 1.0;
    vec4 ClipSpacePosition = vec4(txc * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_InverseProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    vec4 WorldPos = u_InverseView * ViewSpacePosition;
    return WorldPos.xyz;
}

vec3 WorldPosFromDepthPrev(float depth, vec2 txc)
{
    float z = depth * 2.0 - 1.0;
    vec4 ClipSpacePosition = vec4(txc * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_PrevInverseProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    vec4 WorldPos = u_PrevInverseView * ViewSpacePosition;
    return WorldPos.xyz;
}

vec3 ProjectPositionPrevious(vec3 pos)
{
	vec3 WorldPos = pos;
	vec4 ProjectedPosition = u_PrevProjection * u_PrevView * vec4(WorldPos, 1.0f);
	ProjectedPosition.xyz /= ProjectedPosition.w;

	return ProjectedPosition.xyz;
}

vec2 Reprojection(vec3 pos) 
{
	return ProjectPositionPrevious(pos).xy * 0.5f + 0.5f;
}

float GetLuminance(vec3 color) 
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

bool InScreenSpace(vec2 x)
{
    return x.x < 1.0f && x.x > 0.0f && x.y < 1.0f && x.y > 0.0f;
}

bool InThresholdedScreenSpace(vec2 x)
{
	const float b = 0.0035f;
    return x.x < 1.0f - b && x.x > b && x.y < 1.0f - b && x.y > b;
}

vec3 SampleNormal(sampler2D samp, vec2 txc) { 
	return texture(samp, txc).xyz;
}

float LuminanceAccurate(in vec3 color) {
    return dot(color, vec3(0.2722287168, 0.6740817658, 0.0536895174));
}

void main()
{
	float BaseDepth = texture(u_CurrentDepthTexture, v_TexCoords).x;
	vec3 BasePosition = WorldPosFromDepth(BaseDepth, v_TexCoords).xyz;
	vec3 BaseNormal = SampleNormal(u_CurrentNormalTexture, v_TexCoords).xyz;
	vec3 BaseLighting = texture(u_CurrentLighting, v_TexCoords).xyz;
	float BaseAO = texture(u_CurrentAO, v_TexCoords).r;

	vec2 TexelSize = 1.0f / textureSize(u_CurrentLighting, 0);

	float TotalWeight = 0.0f;
	vec3 SumLighting = vec3(0.0f);
	float SumAO = 0.0f;
	float SumLuminosity = 0.0f;
	float SumSPP = 0.0f;
	float SumMoment = 0.0f;
	vec2 ReprojectedCoord = Reprojection(BasePosition.xyz);
	vec2 PositionFract = fract(ReprojectedCoord);
	vec2 OneMinusPositionFract = 1.0f - PositionFract;
	float BaseLuminosity = LuminanceAccurate(BaseLighting);

	// Atrous weights : 
	// https://www.eso.org/sci/software/esomidas/doc/user/18NOV/volb/node317.html
	float Weights[5] = float[5](3.0f / 32.0f,
								3.0f / 32.0f,
								9.0f / 64.0f,
								3.0f / 32.0f,
								3.0f / 32.0f);

	const vec2 Offsets[5] = vec2[5](vec2(1, 0), vec2(0, 1), vec2(0.0f), vec2(-1, 0), vec2(0, -1));

	// Sample neighbours and hope to find a good sample : 
	for (int i = 0 ; i < 5 ; i++)
	{
		vec2 Offset = Offsets[i];
		vec2 SampleCoord = ReprojectedCoord + vec2(Offset.x, Offset.y) * TexelSize;
		if (!InThresholdedScreenSpace(SampleCoord)) { continue; }

		float PreviousDepth = texture(u_PreviousDepthTexture, SampleCoord).x;
		vec3 PreviousPositionAt = WorldPosFromDepthPrev(PreviousDepth, SampleCoord);
		vec3 PreviousNormalAt = SampleNormal(u_PreviousNormalTexture, SampleCoord).xyz;
		vec3 PositionDifference = PreviousPositionAt.xyz - BasePosition.xyz;
		float PositionError = dot(PositionDifference, PositionDifference);
		float CurrentWeight = Weights[i];

		// todo : adjust this because this causes a fuckton of problems!
		const float PositionTolerance = 4.0f;
		const float PositionToleranceReal = pow(PositionTolerance, 1.5f);
		if (PositionError < PositionToleranceReal)
		{
			float NormalWeight = pow(abs(dot(BaseNormal, PreviousNormalAt)), 4.0f);
			CurrentWeight = CurrentWeight * NormalWeight;
			vec3 PreviousUtility = texture(u_PreviousUtility, SampleCoord).xyz;
			vec3 PreviousLighting = texture(u_PreviousLighting, SampleCoord).xyz;

			SumLighting += PreviousLighting * CurrentWeight;
			SumSPP += PreviousUtility.x * CurrentWeight;
			SumMoment += PreviousUtility.y * CurrentWeight;
			SumLuminosity += PreviousUtility.z * CurrentWeight;
			SumAO += texture(u_PreviousAO, SampleCoord).r * CurrentWeight;
			TotalWeight += CurrentWeight;
		}
	}

	if (TotalWeight > 0.0f) { 
		SumLighting /= TotalWeight;
		SumMoment /= TotalWeight;
		SumSPP /= TotalWeight;
		SumLuminosity /= TotalWeight;
		SumAO /= TotalWeight;
	}

	const bool AccumulateAll = false;

	float BlendFactor = max(1.0f / (SumSPP + 1.0f), 0.05f);
	float MomentFactor = max(1.0f / (SumSPP + 1.0f), 0.05f);
	
	if (AccumulateAll) {
		BlendFactor = 0.01f;
	}

	float UtilitySPP = SumSPP + 1.0;
	float UtilityMoment = (1 - MomentFactor) * SumMoment + MomentFactor * pow(BaseLuminosity, 2.0f);
	
	float CurrentNoisyLuma = BaseLuminosity;
	float StoreLuma = mix(SumLuminosity, CurrentNoisyLuma, BlendFactor);

	o_Lighting = mix(SumLighting, BaseLighting, BlendFactor);
	o_AO = mix(SumAO, BaseAO, BlendFactor);
	o_Utility = vec3(UtilitySPP, UtilityMoment, StoreLuma);
}


