#version 330 core

#define ESTIMATE_WEIGHT_BASED_ON_NEIGHBOURS

layout (location = 0) out vec3 o_Lighting;
layout (location = 1) out float o_Variance;
layout (location = 2) out float o_AO;

in vec2 v_TexCoords;

uniform sampler2D u_Lighting;

uniform sampler2D u_DepthTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_VarianceTexture;
uniform sampler2D u_AO;

uniform vec2 u_Dimensions;
uniform int u_Step;

uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;


uniform float u_zNear;
uniform float u_zFar;



const float u_ColorPhiBias = 2.6f;
const float POSITION_THRESH = 4.0f;

vec3 WorldPosFromDepth(float depth, vec2 txc)
{
    float z = depth * 2.0 - 1.0;
    vec4 ClipSpacePosition = vec4(txc * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_InverseProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    vec4 WorldPos = u_InverseView * ViewSpacePosition;
    return WorldPos.xyz;
}

float GetLuminance(vec3 color) 
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

bool InScreenSpace(in vec2 v) 
{
    return v.x < 1.0f && v.x > 0.0f && v.y < 1.0f && v.y > 0.0f;
}

float LuminanceAccurate(in vec3 color) {
    return dot(color, vec3(0.2722287168, 0.6740817658, 0.0536895174));
}


vec3 Saturate(vec3 x)
{
	return clamp(x, 0.0f, 1.0f);
}

float GetVarianceEstimate(out float BaseVariance)
{
#ifdef ESTIMATE_WEIGHT_BASED_ON_NEIGHBOURS
	vec2 TexelSize = 1.0f / textureSize(u_Lighting, 0);
	float VarianceSum = 0.0f;

	const float Kernel[3] = float[3](1.0 / 4.0, 1.0 / 8.0, 1.0 / 16.0);

	for (int x = -1 ; x <= 1 ; x++)
	{
		for (int y = -1 ; y <= 1 ; y++)
		{
			vec2 SampleCoord = v_TexCoords + vec2(x, y) * TexelSize;
			
			if (!InScreenSpace(SampleCoord)) { continue ; }

			float KernelValue = Kernel[abs(x) + abs(y)]; 
			float V = texture(u_VarianceTexture, SampleCoord).r;

			if (x == 0 && y == 0) { BaseVariance = V; }

			VarianceSum += V * KernelValue;
		}
	}

	return VarianceSum;
#else 
	float x = texture(u_VarianceTexture, v_TexCoords).r;
	BaseVariance = x;
	return x;
#endif
}

float SHToY(vec4 shY)
{
    return max(0, 3.544905f * shY.w);
}

float linearizeDepth(float depth)
{
	return (2.0 * u_zNear) / (u_zFar + u_zNear - depth * (u_zFar - u_zNear));
}

float sqr(float x) { return x * x; }
float GetSaturation(in vec3 v) { return length(v); }

void main()
{
	const float AtrousWeights[3] = float[3]( 1.0f, 2.0f / 3.0f, 1.0f / 6.0f );
	const float AtrousWeights2[5] = float[5] (0.0625, 0.25, 0.375, 0.25, 0.0625);

	vec2 TexelSize = 1.0f / u_Dimensions;
	vec4 TotalColor = vec4(0.0f);

	bool FilterAO = u_Step <= 6;

	float BaseDepth = texture(u_DepthTexture, v_TexCoords).x;
	float BaseLinearDepth = linearizeDepth(BaseDepth);
	vec3 BaseNormal = texture(u_NormalTexture, v_TexCoords).xyz;
	vec3 BaseLighting = texture(u_Lighting, v_TexCoords).xyz;
	float BaseLuminance = LuminanceAccurate(BaseLighting);
	float BaseVariance = 0.0f;
	float VarianceEstimate = GetVarianceEstimate(BaseVariance);
	float BaseAO = texture(u_AO, v_TexCoords).r;

	// Start with the base inputs, one iteration of the loop can then be skipped
	vec3 TotalLighting = BaseLighting;
	float TotalWeight = 1.0f;
	float TotalVariance = BaseVariance;
	float TotalAO = BaseAO;
	float TotalAOWeight = 1.0f;
	
	float PhiColor = sqrt(max(0.0f, 1e-10 + VarianceEstimate));
	PhiColor /= max(u_ColorPhiBias, 0.4f); 

	float PhiPosition = 0.4f * u_Step;

	for (int x = -1 ; x <= 1 ; x++)
	{
		for (int y = -2 ; y <= 2 ; y++)
		{
			vec2 SampleCoord = v_TexCoords + (vec2(x, y) * float(u_Step)) * TexelSize;
			if (!InScreenSpace(SampleCoord)) { continue; }
			if (x == 0 && y == 0) { continue ; }

			float SampleDepth = texture(u_DepthTexture, SampleCoord).x;
			float SampleLinearDepth = linearizeDepth(SampleDepth);

			// Weights : 
			float PositionDifference = abs(SampleLinearDepth - BaseLinearDepth);
			float PositionWeight = 1.0f / (PositionDifference + 0.01f);
			PositionWeight = pow(PositionWeight, 1/1000.0f);

			// Samples :
			vec3 SampleLighting = texture(u_Lighting, SampleCoord).xyz;
			vec3 SampleNormal = texture(u_NormalTexture, SampleCoord).xyz;
			float SampleLuma = LuminanceAccurate(SampleLighting);
			float SampleVariance = texture(u_VarianceTexture, SampleCoord).r;

			// :D
			float NormalWeight = pow(max(dot(BaseNormal, SampleNormal), 0.0f), 1e-2);
			float LuminosityWeight = abs(SampleLuma - BaseLuminance) / PhiColor;
			float Weight = exp(-LuminosityWeight - PositionWeight - NormalWeight);
			Weight = max(Weight, 0.0f);

			// Kernel Weights : 
			float XWeight = AtrousWeights[abs(x)];
			float YWeight = AtrousWeights[abs(y)];

			Weight = (XWeight * YWeight) * Weight;
			Weight = max(Weight, 0.01f);

			TotalLighting += SampleLighting * Weight;
			TotalVariance += sqr(Weight) * SampleVariance;
			TotalWeight += Weight;

			if (FilterAO) {
				TotalAO += texture(u_AO, SampleCoord).x * Weight;
				TotalAOWeight += Weight;
			}
		}
	}
	
	TotalLighting /= max(TotalWeight, 0.001f);;
	TotalVariance /= max(sqr(TotalWeight), 0.001f);
	TotalAO /= max(TotalAOWeight, 0.001f);
	
	// Output : 
	o_Lighting = TotalLighting;
	o_Variance = TotalVariance;
	o_AO = TotalAO;

	const bool DontFilter = false;
	const bool DO_SPATIAL = true;

	if (!DO_SPATIAL) { 
		o_Lighting = BaseLighting;
		o_Variance = BaseVariance;
		o_AO = BaseAO;
	}
}