#version 450 core

layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

in vec3 v_WorldPosition[];
in vec3 v_Normal[];

out vec3 g_WorldPosition;
out vec3 g_Normal;

uniform vec3 u_gVolumeSize;

void main()
{
	vec3 p1 = v_WorldPosition[1] - v_WorldPosition[0];
	vec3 p2 = v_WorldPosition[2] - v_WorldPosition[0];
	vec3 p = abs(cross(p1, p2)); 

	for(uint i = 0; i < 3; i++)
	{
		g_WorldPosition = v_WorldPosition[i];
		g_Normal = v_Normal[i];

		if(p.z > p.x && p.z > p.y)
		{
			gl_Position = vec4(g_WorldPosition.x, g_WorldPosition.y, 0.0f, 1.0f) / vec4(u_gVolumeSize.x, u_gVolumeSize.y, 1.0f, 1.0f);
		}
		
		else if (p.x > p.y && p.x > p.z)
		{
			gl_Position = vec4(g_WorldPosition.y, g_WorldPosition.z, 0.0f, 1.0f) / vec4(u_gVolumeSize.y, u_gVolumeSize.z, 1.0f, 1.0f);
		} 
		
		else 
		{
			gl_Position = vec4(g_WorldPosition.x, g_WorldPosition.z, 0.0f, 1.0f) / vec4(u_gVolumeSize.x, u_gVolumeSize.z, 1.0f, 1.0f);
		}

		EmitVertex();
	}

    EndPrimitive();
}