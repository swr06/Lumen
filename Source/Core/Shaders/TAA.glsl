#version 330 core

layout (location = 0) out vec3 o_Color;

in vec2 v_TexCoords;

uniform sampler2D u_CurrentColorTexture;
uniform sampler2D u_DepthTexture;
uniform sampler2D u_PreviousColorTexture;
uniform sampler2D u_PreviousDepthTexture;

uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;
uniform mat4 u_PrevProjection;
uniform mat4 u_PrevView;
uniform mat4 u_InversePrevProjection;
uniform mat4 u_InversePrevView;

uniform bool u_Enabled;


vec2 Reprojection(vec3 WorldPos) 
{
	vec4 ProjectedPosition = u_PrevProjection * u_PrevView * vec4(WorldPos, 1.0f);
	ProjectedPosition.xyz /= ProjectedPosition.w;
	ProjectedPosition.xy = ProjectedPosition.xy * 0.5f + 0.5f;
	return ProjectedPosition.xy;
}

float FastDistance(in vec3 p1, in vec3 p2)
{
	return abs(p1.x - p2.x) + abs(p1.y - p2.y) + abs(p1.z - p2.z);
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

vec3 WorldPosFromDepthPrev(float depth, vec2 txc)
{
    float z = depth * 2.0 - 1.0;
    vec4 ClipSpacePosition = vec4(txc * 2.0 - 1.0, z, 1.0);
    vec4 ViewSpacePosition = u_InversePrevProjection * ClipSpacePosition;
    ViewSpacePosition /= ViewSpacePosition.w;
    vec4 WorldPos = u_InversePrevView * ViewSpacePosition;
    return WorldPos.xyz;
}

vec3 clipAABB(vec3 prevColor, vec3 minColor, vec3 maxColor)
{
    vec3 pClip = 0.5 * (maxColor + minColor); 
    vec3 eClip = 0.5 * (maxColor - minColor); 
    vec3 vClip = prevColor - pClip;
    vec3 vUnit = vClip / eClip;
    vec3 aUnit = abs(vUnit);
    float denom = max(aUnit.x, max(aUnit.y, aUnit.z));
    return denom > 1.0 ? pClip + vClip / denom : prevColor;
}

vec3 ClampColor(vec3 Color) 
{
    vec3 MinColor = vec3(100.0);
	vec3 MaxColor = vec3(-100.0); 
	vec2 TexelSize = 1.0f / textureSize(u_CurrentColorTexture,0);

    for(int x = -1; x <= 1; x++) 
	{
        for(int y = -1; y <= 1; y++) 
		{
            vec3 Sample = texture(u_CurrentColorTexture, v_TexCoords + vec2(x, y) * TexelSize).rgb; 
            MinColor = min(Sample, MinColor); 
			MaxColor = max(Sample, MaxColor); 
        }
    }

    return clipAABB(Color, MinColor, MaxColor);
}



void main()
{
	vec3 CurrentColor = texture(u_CurrentColorTexture, v_TexCoords).rgb;
	float CurrentDepth = texture(u_DepthTexture, v_TexCoords).x;

	// Sky
	if (CurrentDepth > 0.99995f || !u_Enabled) {
		o_Color = CurrentColor.xyz;
		return;
	}

	vec3 WorldPosition = WorldPosFromDepth(CurrentDepth, v_TexCoords).xyz;
	vec2 PreviousCoord = Reprojection(WorldPosition.xyz); 
	float bias = 0.01f;

	if (PreviousCoord.x > bias && PreviousCoord.x < 1.0f-bias &&
		PreviousCoord.y > bias && PreviousCoord.y < 1.0f-bias && 
		v_TexCoords.x > bias && v_TexCoords.x < 1.0f-bias &&
		v_TexCoords.y > bias && v_TexCoords.y < 1.0f-bias)
	{
		// Disocclusion check :
		float PreviousDepth = texture(u_PreviousDepthTexture, PreviousCoord).x;
		vec3 PreviousWorldPosition = WorldPosFromDepthPrev(PreviousDepth, PreviousCoord);
		vec3 PositionDiff = abs(WorldPosition - PreviousWorldPosition);
		float DistanceSquared = dot(PositionDiff, PositionDiff);

		//const float sqrt3 = sqrt(3);
		//if (DistanceSquared > sqrt3) {
		//	o_Color = CurrentColor;
		//	return;
		//}

		// Finally, blend.
		vec3 PrevColor = texture(u_PreviousColorTexture, PreviousCoord).rgb;
		PrevColor = ClampColor(PrevColor);
		vec2 Dimensions = textureSize(u_CurrentColorTexture, 0).xy;
		vec2 velocity = (v_TexCoords - PreviousCoord.xy) * Dimensions;
		float BlendFactor = exp(-length(velocity)) * 0.7f + 0.325f;
		o_Color = mix(CurrentColor.xyz, PrevColor.xyz, clamp(BlendFactor, 0.01f, 0.95f));
	}

	else 
	{
		o_Color = CurrentColor;
	}
}

