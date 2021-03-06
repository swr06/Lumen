#version 330 core

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_TexCoords;
layout (location = 3) in vec3 a_Tangent;
layout (location = 4) in vec3 a_Bitangent;

uniform mat4 u_ModelMatrix;
uniform mat3 u_NormalMatrix;

out mat3 v_TBNMatrix;
out vec2 v_TexCoords;
out vec3 v_FragPosition;
out vec3 v_Normal;

uniform mat4 u_ViewProjection;

void main()
{
	gl_Position = u_ModelMatrix * vec4(a_Position, 1.0f);
	v_FragPosition = gl_Position.xyz;
	gl_Position = u_ViewProjection * gl_Position;
	v_TexCoords = a_TexCoords;
	v_Normal = mat3(u_NormalMatrix) * a_Normal;  

	vec3 T = (vec3(u_ModelMatrix * vec4(a_Tangent, 0.0)));
	vec3 B = (vec3(u_ModelMatrix * vec4(a_Bitangent, 0.0)));
	vec3 N = (vec3(u_ModelMatrix * vec4(a_Normal, 0.0)));
	v_TBNMatrix = mat3(T, B, N);
}