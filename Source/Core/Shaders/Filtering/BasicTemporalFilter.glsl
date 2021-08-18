#version 330 core

layout (location = 0) out vec4 o_Color;

in vec2 v_TexCoords;

uniform sampler2D u_CurrentColorTexture;
uniform sampler2D u_DepthTexture;
uniform sampler2D u_PreviousColorTexture;
uniform sampler2D u_PreviousDepthTexture;

uniform mat4 u_Projection;
uniform mat4 u_View;
uniform mat4 u_PrevProjection;
uniform mat4 u_PrevView;
uniform mat4 u_InverseProjection;
uniform mat4 u_InverseView;

uniform float u_MinimumMix = 0.25f;
uniform float u_MaximumMix = 0.975f;

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

bool InScreenSpace(vec2 x)
{
    return x.x < 1.0f && x.x > 0.0f && x.y < 1.0f && x.y > 0.0f;
}

vec4 ClipColor(vec4 aabbMin, vec4 aabbMax, vec4 prevColor) 
{
    vec4 pClip = (aabbMax + aabbMin) / 2;
    vec4 eClip = (aabbMax - aabbMin) / 2;
    vec4 vClip = prevColor - pClip;
    vec4 vUnit = vClip / eClip;
    vec4 aUnit = abs(vUnit);
    float divisor = max(aUnit.x, max(aUnit.y, aUnit.z));

    if (divisor > 1)
	{
        return pClip + vClip / divisor;
    }

    return prevColor;
}

bool InThresholdedScreenSpace(in vec2 v) 
{
	float b = 0.03f;
	return v.x > b && v.x < 1.0f - b && v.y > b && v.y < 1.0f - b;
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


void main()
{
	vec2 CurrentCoord = v_TexCoords;
	float CurrentDepth = texture(u_DepthTexture, v_TexCoords).r;
	vec3 CurrentPosition = WorldPosFromDepth(CurrentDepth, v_TexCoords);

	if (CurrentDepth < 0.99995)
	{
		vec2 Reprojected;
		Reprojected = Reprojection(CurrentPosition.xyz);

		vec4 CurrentColor = texture(u_CurrentColorTexture, CurrentCoord).rgba;
		vec4 PrevColor = texture(u_PreviousColorTexture, Reprojected);
		float PrevDepth = texture(u_PreviousDepthTexture, Reprojected).x;
		vec3 PrevPosition = WorldPosFromDepth(PrevDepth, Reprojected).xyz;

		float Bias = 0.002f;

		if (Reprojected.x > 0.0 + Bias && Reprojected.x < 1.0 - Bias && Reprojected.y > 0.0 + Bias && Reprojected.y < 1.0 - Bias)
		{
			float d = abs(distance(PrevPosition, CurrentPosition.xyz));
			float t = 8.1f;

			if (d > t) 
			{
				o_Color = CurrentColor;
				return;
			}

			float BlendFactor = d * 0.1f;
			BlendFactor = exp(-BlendFactor);
			BlendFactor = clamp(BlendFactor, clamp(u_MinimumMix, 0.01f, 0.9f), clamp(u_MaximumMix, 0.1f, 0.98f));
			o_Color = mix(CurrentColor, PrevColor, BlendFactor);
		}

		else 
		{
			o_Color = CurrentColor;
		}
	}

	else 
	{
		o_Color = texture(u_CurrentColorTexture, v_TexCoords);
	}
}

