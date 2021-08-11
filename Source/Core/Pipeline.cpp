#include "Pipeline.h"

#include "FpsCamera.h"
#include "GLClasses/Shader.h"
#include "Object.h"
#include "Entity.h"
#include "ModelFileLoader.h"
#include "ModelRenderer.h"
#include "GLClasses/Fps.h"

Lumen::FPSCamera Camera(90.0f, 800.0f / 600.0f);

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
		GLFWwindow* window = GetWindow();
		float camera_speed = 0.1f;

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

	void OnImguiRender(double ts) override
	{
		ImGui::Text("Test!");
	}

	void OnEvent(Lumen::Event e) override
	{
		if (e.type == Lumen::EventTypes::MouseMove)
		{
			Camera.UpdateOnMouseMovement(e.mx, e.my);
		}

		if (e.type == Lumen::EventTypes::WindowResize)
		{
			Camera.SetAspect((float)e.wx / (float)e.wy);
		}
	}


};

void Lumen::StartPipeline()
{
	RayTracerApp app;
	app.Initialize();
	app.SetCursorLocked(true);

	GLClasses::VertexBuffer ScreenQuadVBO;
	GLClasses::VertexArray ScreenQuadVAO;
	GLClasses::Shader MeshShader;

	MeshShader.CreateShaderProgramFromFile("Core/Shaders/BasicVert.glsl", "Core/Shaders/BasicFrag.glsl");
	MeshShader.CompileShaders();

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

	app.SetCursorLocked(false);

	Object Sponza;
	FileLoader::LoadModelFile(&Sponza, "Models/sponza-pbr/Sponza.gltf");
	Entity MainModel(&Sponza);

	MainModel.m_Model = glm::scale(glm::mat4(1.0f), glm::vec3(0.1f));
	MainModel.m_Model = glm::translate(MainModel.m_Model, glm::vec3(0.0f));

	while (!glfwWindowShouldClose(app.GetWindow()))
	{
		app.OnUpdate();

		glEnable(GL_CULL_FACE);
		glEnable(GL_DEPTH_TEST);

		MeshShader.Use();
		MeshShader.SetMatrix4("u_ViewProjection", Camera.GetViewProjection());
		MeshShader.SetInteger("u_AlbedoMap", 0);
		MeshShader.SetInteger("u_NormalMap", 1);
		RenderEntity(MainModel, MeshShader);
		app.FinishFrame();

		GLClasses::DisplayFrameRate(app.GetWindow(), "Lumen ");
	}
}
