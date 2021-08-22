#version 330 core

layout (location = 0) out float o_DownsampledDepth;

in vec2 v_TexCoords;

uniform sampler2D u_DepthBuffer;

void main() {
	vec2 TexelSize = 1.0f / textureSize(u_DepthBuffer, 0);

	float Samples[4];
	Samples[0] = texture(u_DepthBuffer, v_TexCoords + vec2(-1.0f, -1.0f) * TexelSize).x;
	Samples[1] = texture(u_DepthBuffer, v_TexCoords + vec2(-1.0f, 1.0f) * TexelSize).x;
	Samples[2] = texture(u_DepthBuffer, v_TexCoords + vec2(1.0f, -1.0f) * TexelSize).x;
	Samples[3] = texture(u_DepthBuffer, v_TexCoords + vec2(1.0f, 1.0f) * TexelSize).x;
	
	float FinalDepth = 500.0f;
	FinalDepth = min(Samples[0], FinalDepth);
	FinalDepth = min(Samples[1], FinalDepth);
	FinalDepth = min(Samples[2], FinalDepth);
	FinalDepth = min(Samples[3], FinalDepth);

	o_DownsampledDepth = FinalDepth;
}