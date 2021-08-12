#version 440 core

layout (location = 0) out vec3 o_Albedo;
layout (location = 1) out vec3 o_Normal;
layout (location = 2) out vec3 o_PBR;

uniform sampler2DArray u_AlbedoMap;
uniform sampler2DArray u_NormalMap;
uniform sampler2DArray u_MetalnessMap;
uniform sampler2DArray u_RoughnessMap;

in vec2 v_TexCoords;
in vec3 v_FragPosition;
in vec3 v_Normal;
in mat3 v_TBNMatrix;
in flat uint v_TexID;
in flat uint v_TexID2;

void main()
{
	uint AlbedoIDX = v_TexID & 0xFF;
	uint NormalIDX = (v_TexID >> 8) & 0xFF;
	uint RoughnessIDX = v_TexID2 & 0xFF;
	uint MetalnessIDX = (v_TexID2 >> 8) & 0xFF;
	o_Albedo = texture(u_AlbedoMap, vec3(v_TexCoords, float(AlbedoIDX))).xyz;
	o_Normal = v_TBNMatrix * (texture(u_NormalMap, vec3(v_TexCoords, float(NormalIDX))).xyz * 2.0f - 1.0f);
	o_PBR = vec3(texture(u_RoughnessMap, vec3(v_TexCoords, float(RoughnessIDX))).r, 
					texture(u_MetalnessMap, vec3(v_TexCoords, float(MetalnessIDX))).r, 
					1.0f);
}
