#define VOXEL_VOLUME_X 256
#define VOXEL_VOLUME_Y 256
#define VOXEL_VOLUME_Z 256

#include "Pipeline.h"

#include "FpsCamera.h"
#include "GLClasses/Shader.h"
#include "Object.h"
#include "Entity.h"
#include "ModelFileLoader.h"
#include "ModelRenderer.h"
#include "GLClasses/Fps.h"
#include "GLClasses/Framebuffer.h"
#include "ShaderManager.h"
#include "GLClasses/DepthBuffer.h"
#include "ShadowRenderer.h"
#include "GLClasses/CubeTextureMap.h"
#include "Voxelizer.h"

#include <string>

Lumen::FPSCamera Camera(90.0f, 800.0f / 600.0f);

static bool vsync = false;
static float SunTick = 50.0f;
static glm::vec3 SunDirection = glm::vec3(0.1f, -1.0f, 0.1f);
static glm::vec3 VoxelizationPosition;

static float IndirectTraceResolution = 0.5f;
static float MixFactor = 0.975f;



class RayTracerApp : public Lumen::Application
{
public:

	RayTracerApp()
	{
		m_Width = 800;
		m_Height = 600;
	}

	void OnUserCreate(double ts) override
	{
	
	}

	void OnUserUpdate(double ts) override
	{
		glfwSwapInterval((int)vsync);

		GLFWwindow* window = GetWindow();
		float camera_speed = glfwGetKey(window, GLFW_KEY_LEFT_CONTROL) ? 2.6f : 1.0f; 

		if (GetCursorLocked()) {
			if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS)
				Camera.ChangePosition(Camera.GetFront() * camera_speed);

			if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS)
				Camera.ChangePosition(-(Camera.GetFront() * camera_speed));

			if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS)
				Camera.ChangePosition(-(Camera.GetRight() * camera_speed));

			if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS)
				Camera.ChangePosition(Camera.GetRight() * camera_speed);

			if (glfwGetKey(window, GLFW_KEY_SPACE) == GLFW_PRESS)
				Camera.ChangePosition(Camera.GetUp() * camera_speed);

			if (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS)
				Camera.ChangePosition(-(Camera.GetUp() * camera_speed));

		}
	}

	void OnImguiRender(double ts) override
	{
		ImGui::Text("Position : %f,  %f,  %f", Camera.GetPosition().x, Camera.GetPosition().y, Camera.GetPosition().z);
		ImGui::Text("Front : %f,  %f,  %f", Camera.GetFront().x, Camera.GetFront().y, Camera.GetFront().z);
		//ImGui::SliderFloat("Sun Time ", &SunTick, 0.1f, 256.0f);
		ImGui::SliderFloat("Indirect Resolution : ", &IndirectTraceResolution, 0.1f, 1.0f);
		ImGui::SliderFloat3("Sun Dir : ", &SunDirection[0], -1.0f, 1.0f);
		ImGui::SliderFloat("Indirect Mix : ", &MixFactor, 0.01f, 0.995);
	}

	void OnEvent(Lumen::Event e) override
	{
		if (e.type == Lumen::EventTypes::MouseMove && GetCursorLocked())
		{
			Camera.UpdateOnMouseMovement(e.mx, e.my);
		}

		if (e.type == Lumen::EventTypes::WindowResize)
		{
			Camera.SetAspect((float)e.wx / (float)e.wy);
		}

		if (e.type == Lumen::EventTypes::KeyPress && e.key == GLFW_KEY_ESCAPE) {
			exit(0);
		}

		if (e.type == Lumen::EventTypes::KeyPress && e.key == GLFW_KEY_F1)
		{
			this->SetCursorLocked(!this->GetCursorLocked());
		}

		if (e.type == Lumen::EventTypes::KeyPress && e.key == GLFW_KEY_F2 && this->GetCurrentFrame() > 5)
		{
			Lumen::ShaderManager::RecompileShaders();
		}

		if (e.type == Lumen::EventTypes::KeyPress && e.key == GLFW_KEY_F5)
		{
			glm::vec3 SetPosition = glm::vec3(-104.384857, 30.665455, -13.041096);
			glm::vec3 Front = glm::vec3(0.998306, -0.056693, 0.13069);
			Camera.SetPosition(SetPosition);
			Camera.SetFront(Front);
		}

		if (e.type == Lumen::EventTypes::KeyPress && e.key == GLFW_KEY_V && this->GetCurrentFrame() > 5)
		{
			vsync = !vsync;
		}
	}


};

void UnbindEverything() {
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glUseProgram(0);
}

float Align(float value, float size)
{
	return std::floor(value / size) * size;
}

glm::vec3 AlignVec3(const glm::vec3& v, const glm::vec3& a)
{
	return glm::vec3(
		Align(v.x, a.x), Align(v.y, a.y), Align(v.z, a.z)
	);
}


// GBuffers : 
GLClasses::Framebuffer GBuffer1(16, 16, { {GL_RGB16F, GL_RGB, GL_FLOAT, true, true}, {GL_RGB16F, GL_RGB, GL_FLOAT, true, true}, {GL_RGB16F, GL_RGB, GL_FLOAT, true, true},  {GL_RGB, GL_RGB, GL_UNSIGNED_BYTE, false, false} }, false, true);
GLClasses::Framebuffer GBuffer2(16, 16, { {GL_RGB16F, GL_RGB, GL_FLOAT, true, true}, {GL_RGB16F, GL_RGB, GL_FLOAT, true, true}, {GL_RGB16F, GL_RGB, GL_FLOAT, true, true},  {GL_RGB, GL_RGB, GL_UNSIGNED_BYTE, false, false} }, false, true);

// Lighting 
GLClasses::Framebuffer LightingPass(16, 16, {GL_RGB16F, GL_RGB, GL_FLOAT, true, true}, false, false);

// Indirect : 
GLClasses::Framebuffer IndirectLighting(16, 16, { {GL_RGB16F, GL_RGB, GL_FLOAT, true, true}, {GL_RED, GL_RED, GL_UNSIGNED_BYTE, true, true} }, false, false);
GLClasses::Framebuffer IndirectTemporal_1(16, 16, { {GL_RGB16F, GL_RGB, GL_FLOAT, true, true} }, false, false);
GLClasses::Framebuffer IndirectTemporal_2(16, 16, { {GL_RGB16F, GL_RGB, GL_FLOAT, true, true} }, false, false);


void Lumen::StartPipeline()
{
	RayTracerApp app;
	app.Initialize();
	app.SetCursorLocked(true);


	GLClasses::VertexBuffer ScreenQuadVBO;
	GLClasses::VertexArray ScreenQuadVAO;

	GLClasses::DepthBuffer Shadowmap(3584, 3584);
	GLClasses::Texture BlueNoise;
	GLClasses::CubeTextureMap Skymap;

	VoxelVolume MainVoxelVolume;

	Skymap.CreateCubeTextureMap(
		{
		"Res/Skymap/right.bmp",
		"Res/Skymap/left.bmp",
		"Res/Skymap/top.bmp",
		"Res/Skymap/bottom.bmp",
		"Res/Skymap/front.bmp",
		"Res/Skymap/back.bmp"
		}, true
	);

	BlueNoise.CreateTexture("Res/blue_noise.png", false, false);

	MainVoxelVolume.CreateVoxelVolume();

	{
		unsigned long long CurrentFrame = 0;
		float QuadVertices_NDC[] =
		{
			-1.0f,  1.0f,  0.0f, 1.0f, -1.0f, -1.0f,  0.0f, 0.0f,
			 1.0f, -1.0f,  1.0f, 0.0f, -1.0f,  1.0f,  0.0f, 1.0f,
			 1.0f, -1.0f,  1.0f, 0.0f,  1.0f,  1.0f,  1.0f, 1.0f
		};

		ScreenQuadVAO.Bind();
		ScreenQuadVBO.Bind();
		ScreenQuadVBO.BufferData(sizeof(QuadVertices_NDC), QuadVertices_NDC, GL_STATIC_DRAW);
		ScreenQuadVBO.VertexAttribPointer(0, 2, GL_FLOAT, 0, 4 * sizeof(GLfloat), 0);
		ScreenQuadVBO.VertexAttribPointer(1, 2, GL_FLOAT, 0, 4 * sizeof(GLfloat), (void*)(2 * sizeof(GLfloat)));
		ScreenQuadVAO.Unbind();
	}


	// Create Shaders
	ShaderManager::CreateShaders();


	GLClasses::Shader& GBufferShader = ShaderManager::GetShader("GBUFFER");
	GLClasses::Shader& LightingShader = ShaderManager::GetShader("LIGHTING_PASS");
	GLClasses::Shader& FinalShader = ShaderManager::GetShader("FINAL");
	GLClasses::Shader& IndirectRT = ShaderManager::GetShader("INDIRECT_RT");
	GLClasses::Shader& TemporalFilter = ShaderManager::GetShader("BASIC_TEMPORAL");


	glm::mat4 CurrentProjection, CurrentView;
	glm::mat4 PreviousProjection, PreviousView;
	glm::vec3 CurrentPosition, PreviousPosition;
	glm::vec3 CurrentAlignedPosition, PreviousAlignedPosition;
	

	app.SetCursorLocked(true);

	Object Sponza;
	FileLoader::LoadModelFile(&Sponza, "Models/sponza-pbr/Sponza.gltf");
	Entity MainModel(&Sponza);

	MainModel.m_Model = glm::scale(glm::mat4(1.0f), glm::vec3(0.2f));
	MainModel.m_Model = glm::translate(MainModel.m_Model, glm::vec3(0.0f));

	while (!glfwWindowShouldClose(app.GetWindow()))
	{
		auto& GBuffer = (app.GetCurrentFrame() % 2 == 0) ? GBuffer1 : GBuffer2;
		auto& PrevGBuffer = (app.GetCurrentFrame() % 2 == 0) ? GBuffer2 : GBuffer1;
		auto& IndirectTemporalCurr = (app.GetCurrentFrame() % 2 == 0) ? IndirectTemporal_1 : IndirectTemporal_2;
		auto& IndirectTemporalPrev = (app.GetCurrentFrame() % 2 == 0) ? IndirectTemporal_2 : IndirectTemporal_1;

		GBuffer.SetSize(app.GetWidth(), app.GetHeight());
		PrevGBuffer.SetSize(app.GetWidth(), app.GetHeight());
		LightingPass.SetSize(app.GetWidth(), app.GetHeight());
		IndirectLighting.SetSize(floor(app.GetWidth() * IndirectTraceResolution), floor(app.GetHeight() * IndirectTraceResolution));
		IndirectTemporalCurr.SetSize(floor(app.GetWidth() * IndirectTraceResolution), floor(app.GetHeight() * IndirectTraceResolution));
		IndirectTemporalPrev.SetSize(floor(app.GetWidth() * IndirectTraceResolution), floor(app.GetHeight() * IndirectTraceResolution));

		// App update 
		app.OnUpdate();

		PreviousProjection = CurrentProjection;
		PreviousView = CurrentView;
		PreviousPosition = CurrentPosition;
		PreviousAlignedPosition = CurrentAlignedPosition;
		CurrentProjection = Camera.GetProjectionMatrix();
		CurrentView = Camera.GetViewMatrix();
		CurrentPosition = Camera.GetPosition();
		CurrentAlignedPosition = AlignVec3(CurrentPosition, glm::vec3(12.0f));

		if (glfwGetKey(app.GetWindow(), GLFW_KEY_F2))
		{
			MainVoxelVolume.Recompile();
		}

		if (app.GetCurrentFrame() % 8 == 0)
		{
			// Shadow pass 
			RenderShadowMap(Shadowmap, SunDirection, { &MainModel }, Camera.GetViewProjection());
		}

		// Render GBuffer
		glEnable(GL_CULL_FACE);
		glEnable(GL_DEPTH_TEST);
		GBuffer.Bind();
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		GBufferShader.Use();
		GBufferShader.SetMatrix4("u_ViewProjection", Camera.GetViewProjection());
		GBufferShader.SetInteger("u_AlbedoMap", 0);
		GBufferShader.SetInteger("u_NormalMap", 1);
		GBufferShader.SetInteger("u_RoughnessMap", 2);
		GBufferShader.SetInteger("u_MetalnessMap", 3);
		GBufferShader.SetInteger("u_MetalnessRoughnessMap", 5);
		RenderEntity(MainModel, GBufferShader);
		UnbindEverything();

		// Voxelization : 
		int UpdateFreq = 30;

		if (app.GetCurrentFrame() % UpdateFreq == 0 || CurrentAlignedPosition != PreviousAlignedPosition)
		{
			// Voxelize : 
			MainVoxelVolume.VoxelizeScene(&Camera, Shadowmap.GetDepthTexture(), SunDirection, { &MainModel }, GetLightViewProjection(SunDirection));


			// Gen DF 
			MainVoxelVolume.GenerateDistanceField();

			VoxelizationPosition = Camera.GetPosition();
		}
		
		// Post processing passes here : 
		glDisable(GL_CULL_FACE);
		glDisable(GL_DEPTH_TEST);

		//
		// Indirect :

		IndirectRT.Use();
		IndirectLighting.Bind();
		
		IndirectRT.SetInteger("u_AlbedoTexture", 0);
		IndirectRT.SetInteger("u_NormalTexture", 1);
		IndirectRT.SetInteger("u_DepthTexture", 3);
		IndirectRT.SetInteger("u_ShadowTexture", 4);
		IndirectRT.SetInteger("u_BlueNoise", 5);
		IndirectRT.SetInteger("u_Skymap", 6);

		IndirectRT.SetInteger("u_VoxelVolume", 7);
		IndirectRT.SetInteger("u_VoxelDFVolume", 8);

		IndirectRT.SetMatrix4("u_Projection", Camera.GetProjectionMatrix());
		IndirectRT.SetMatrix4("u_View", Camera.GetViewMatrix());
		IndirectRT.SetMatrix4("u_InverseProjection", glm::inverse(Camera.GetProjectionMatrix()));
		IndirectRT.SetMatrix4("u_InverseView", glm::inverse(Camera.GetViewMatrix()));
		IndirectRT.SetMatrix4("u_LightVP", GetLightViewProjection(SunDirection));
		IndirectRT.SetVector2f("u_Dims", glm::vec2(app.GetWidth(), app.GetHeight()));
		IndirectRT.SetVector3f("u_LightDirection", SunDirection);
		IndirectRT.SetVector3f("u_ViewerPosition", Camera.GetPosition());
		IndirectRT.SetVector3f("u_VoxelizationPosition", VoxelizationPosition);

		IndirectRT.SetFloat("u_Time", glfwGetTime());
		IndirectRT.SetInteger("WORLD_SIZE_X", VOXEL_VOLUME_X);
		IndirectRT.SetInteger("WORLD_SIZE_Y", VOXEL_VOLUME_Y);
		IndirectRT.SetInteger("WORLD_SIZE_Z", VOXEL_VOLUME_Z);

		IndirectRT.SetFloat("u_zNear", 0.1f);
		IndirectRT.SetFloat("u_zFar", 1000.0f);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetTexture(0));

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetTexture(2));

		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetTexture(3));

		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetDepthBuffer());

		glActiveTexture(GL_TEXTURE4);
		glBindTexture(GL_TEXTURE_2D, Shadowmap.GetDepthTexture());

		glActiveTexture(GL_TEXTURE5);
		glBindTexture(GL_TEXTURE_2D, BlueNoise.GetTextureID());

		glActiveTexture(GL_TEXTURE6);
		glBindTexture(GL_TEXTURE_CUBE_MAP, Skymap.GetID());

		glActiveTexture(GL_TEXTURE7);
		glBindTexture(GL_TEXTURE_3D, MainVoxelVolume.m_VoxelVolume);
		glActiveTexture(GL_TEXTURE8);
		glBindTexture(GL_TEXTURE_3D, MainVoxelVolume.m_DistanceFieldVolume);

		ScreenQuadVAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		ScreenQuadVAO.Unbind();

		// Temporal filter 

		TemporalFilter.Use();
		IndirectTemporalCurr.Bind();

		TemporalFilter.SetInteger("u_CurrentColorTexture", 0);
		TemporalFilter.SetInteger("u_PreviousColorTexture", 1);
		TemporalFilter.SetInteger("u_DepthTexture", 2);
		TemporalFilter.SetInteger("u_PreviousDepthTexture", 3);

		TemporalFilter.SetMatrix4("u_Projection", Camera.GetProjectionMatrix());
		TemporalFilter.SetMatrix4("u_View", Camera.GetViewMatrix());
		TemporalFilter.SetMatrix4("u_PrevProjection", PreviousProjection);
		TemporalFilter.SetMatrix4("u_PrevView", PreviousView);
		TemporalFilter.SetMatrix4("u_InverseProjection", glm::inverse(Camera.GetProjectionMatrix()));
		TemporalFilter.SetMatrix4("u_InverseView", glm::inverse(Camera.GetViewMatrix()));

		TemporalFilter.SetFloat("u_MinimumMix", 0.25f);
		TemporalFilter.SetFloat("u_MaximumMix", MixFactor);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, IndirectLighting.GetTexture(0));

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, IndirectTemporalPrev.GetTexture(0));

		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetDepthBuffer());

		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, PrevGBuffer.GetDepthBuffer());

		ScreenQuadVAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		ScreenQuadVAO.Unbind();

		// Lighting pass : 

		LightingShader.Use();
		LightingPass.Bind();

		LightingShader.SetInteger("u_AlbedoTexture", 0);
		LightingShader.SetInteger("u_NormalTexture", 1);
		LightingShader.SetInteger("u_PBRTexture", 2);
		LightingShader.SetInteger("u_DepthTexture", 3);
		LightingShader.SetInteger("u_ShadowTexture", 4);
		LightingShader.SetInteger("u_BlueNoise", 5);
		LightingShader.SetInteger("u_Skymap", 6);
		LightingShader.SetInteger("u_IndirectDiffuse", 7);
		LightingShader.SetInteger("u_VXAO", 8);

		LightingShader.SetMatrix4("u_Projection", Camera.GetProjectionMatrix());
		LightingShader.SetMatrix4("u_View", Camera.GetViewMatrix());
		LightingShader.SetMatrix4("u_InverseProjection", glm::inverse(Camera.GetProjectionMatrix()));
		LightingShader.SetMatrix4("u_InverseView", glm::inverse(Camera.GetViewMatrix()));
		LightingShader.SetMatrix4("u_LightVP", GetLightViewProjection(SunDirection));
		LightingShader.SetVector2f("u_Dims", glm::vec2(app.GetWidth(), app.GetHeight()));


		LightingShader.SetVector3f("u_LightDirection", SunDirection);
		LightingShader.SetVector3f("u_ViewerPosition", Camera.GetPosition());

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetTexture(0));

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetTexture(1));

		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetTexture(3));

		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, GBuffer.GetDepthBuffer());

		glActiveTexture(GL_TEXTURE4);
		glBindTexture(GL_TEXTURE_2D, Shadowmap.GetDepthTexture());

		glActiveTexture(GL_TEXTURE5);
		glBindTexture(GL_TEXTURE_2D, BlueNoise.GetTextureID());

		glActiveTexture(GL_TEXTURE6);
		glBindTexture(GL_TEXTURE_CUBE_MAP, Skymap.GetID());

		glActiveTexture(GL_TEXTURE7);
		glBindTexture(GL_TEXTURE_2D, IndirectTemporalCurr.GetTexture(0));
		glActiveTexture(GL_TEXTURE8);
		glBindTexture(GL_TEXTURE_2D, IndirectLighting.GetTexture(1));

		ScreenQuadVAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		ScreenQuadVAO.Unbind();



		// Final
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glViewport(0, 0, app.GetWidth(), app.GetHeight());

		FinalShader.Use();
		FinalShader.SetInteger("u_MainTexture", 0);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, LightingPass.GetTexture(0));

		ScreenQuadVAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		ScreenQuadVAO.Unbind();

		// Finish : 
		glFinish();
		app.FinishFrame();
		GLClasses::DisplayFrameRate(app.GetWindow(), "Lumen ");

	}
}
