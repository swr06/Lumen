#version 450 core

#define VOXEL_SIZE 1

layout (location = 0) in vec3 a_Position;
layout (location = 1) in uvec3 a_NormalTangentData;

uniform mat4 u_ModelMatrix;
uniform mat4 u_ViewProjection;
uniform mat3 u_NormalMatrix;

uniform vec3 u_PlayerPosition;

out vec3 v_WorldPosition;
out vec3 v_Normal;

void main()
{
	v_WorldPosition = vec3(u_ModelMatrix * vec4(a_Position, 1.0f)) ;
	v_WorldPosition -= u_PlayerPosition;

	vec2 Data_0 = unpackHalf2x16(a_NormalTangentData.x);
	vec2 Data_1 = unpackHalf2x16(a_NormalTangentData.y);
	vec3 Normal = vec3(Data_0.x, Data_0.y, Data_1.x);
	v_Normal =  Normal;  
	gl_Position = u_ViewProjection * vec4(v_WorldPosition, 1.0f);
}