#version 330 core

layout (location = 0) out vec3 o_Lighting;
layout (location = 1) out float o_Variance;

in vec2 v_TexCoords;

uniform sampler2D u_DepthTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_Lighting;
uniform sampler2D u_Utility;

uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;


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



void main()
{ 
    vec2 Dimensions = textureSize(u_Lighting, 0);
    vec2 TexelSize = 1.0f / Dimensions;

    float BaseDepth = texture(u_DepthTexture, v_TexCoords).x;
    vec3 BasePosition = WorldPosFromDepth(BaseDepth, v_TexCoords);
    vec3 BaseNormal = texture(u_NormalTexture, v_TexCoords).xyz;

    vec3 BaseUtility = texture(u_Utility, v_TexCoords).xyz;

    vec3 BaseLighting = texture(u_Lighting, v_TexCoords).xyz;
    float BaseLuminosity = LuminanceAccurate(BaseLighting);

    float SPP = BaseUtility.x;
    float BaseMoment = BaseUtility.y;

    float TotalWeight = 0.0f;
    float TotalMoment = 0.0f;
    vec3 TotalLighting = vec3(0.0f);
    float TotalLuminosity = 0.0f;
    float TotalWeight2 = 0.0f;
    float Variance = 0.0f;

    const float SPP_THRESH = 4.0f;
    const float PhiPosition = 0.4f * 2.0f;

    if (SPP < SPP_THRESH)
    {
        for (int x = -2 ; x <= 2 ; x++) 
        {
            for (int y = -2 ; y <= 2 ; y++)
            {
                vec2 SampleCoord = v_TexCoords + vec2(x, y) * TexelSize;

                if (!InScreenSpace(SampleCoord)) { continue; }

                float SampleDepth = texture(u_DepthTexture, SampleCoord).x;
                vec3 SamplePosition = WorldPosFromDepth(SampleDepth, SampleCoord).xyz;

                // Weights : 
                vec3 PositionDifference = abs(SamplePosition - BasePosition);
                float DistSqr = dot(PositionDifference, PositionDifference);
                float PositionWeight = abs(sqrt(DistSqr)) / (PhiPosition * length(vec2(x,y)));
               
             
                vec3 SampleNormal = texture(u_NormalTexture, SampleCoord).xyz;
                vec3 SampleUtility = texture(u_Utility, SampleCoord).xyz;
                float SampleMoment = SampleUtility.y;

                vec3 SampleLighting = texture(u_Lighting, SampleCoord).xyz;
                float SampleLuminosity = LuminanceAccurate(SampleLighting);

                float NormalWeight = pow(max(dot(BaseNormal, SampleNormal), 0.0f), 1e-2);
                float LuminosityWeight = abs(SampleLuminosity - BaseLuminosity) / 1.0e1;
                float Weight = exp(-LuminosityWeight - PositionWeight - NormalWeight);
                float Weight_2 = NormalWeight;

                Weight = max(Weight, 0.015f);
                Weight_2 = max(Weight_2, 0.015f);

                TotalWeight += Weight;
                TotalMoment += SampleMoment * Weight_2;

                TotalLighting += SampleLighting * Weight;
                TotalLuminosity += SampleLuminosity * Weight_2;
                TotalWeight2 += Weight_2;
                
            }
        }

        if (TotalWeight > 0.0f) 
        {
            TotalMoment /= TotalWeight2;
            TotalLuminosity /= TotalWeight2;
            TotalLighting /= TotalWeight;
        }


        o_Lighting = TotalLighting;

        float AccumulatedLuminosity = TotalLuminosity;
        AccumulatedLuminosity = AccumulatedLuminosity * AccumulatedLuminosity;
        Variance = TotalMoment - AccumulatedLuminosity;
	    Variance *= SPP_THRESH / SPP;
    } 


    else 
    {
        o_Lighting = BaseLighting;
        Variance = BaseMoment - BaseLuminosity * BaseLuminosity;
    }

    bool DO_SPATIAL = true;

    if (!DO_SPATIAL) {
         o_Lighting = BaseLighting;
        Variance = BaseMoment - BaseLuminosity * BaseLuminosity;
    }

    o_Variance = Variance;
}