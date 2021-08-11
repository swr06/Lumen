#version 440 core

in vec2 v_TexCoords;
in vec3 v_FragPosition;
in vec3 v_Normal;
in mat3 v_TBNMatrix;

layout (location = 0) out vec3 o_Color;

uniform vec4 u_Color;

uniform sampler2D u_AlbedoMap;
uniform sampler2D u_SpecularMap; 
uniform sampler2D u_NormalMap;
uniform sampler2D u_MetalnessMap;
uniform sampler2D u_RoughnessMap;
uniform sampler2D u_AOMap;

void main()
{
	o_Color = texture(u_AlbedoMap, v_TexCoords).xyz;
}
