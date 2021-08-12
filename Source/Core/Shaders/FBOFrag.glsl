#version 330 core

in vec2 v_TexCoords;
layout(location = 0) out vec4 o_Color;

uniform sampler2D u_AlbedoTexture;

void main()
{
    o_Color.xyz = vec3(texture(u_AlbedoTexture, v_TexCoords).xyz );
    o_Color.w = 1.0f;
}
