#include "Mesh.h"

namespace Lumen
{
	Mesh::Mesh(const uint32_t number) : m_VertexBuffer(GL_ARRAY_BUFFER), m_MeshNumber(number)
	{
		/*
		Setup all the ogl objects
		*/
		m_VertexArray.Bind();
		m_VertexBuffer.Bind();
		m_IndexBuffer.Bind();

		m_VertexBuffer.VertexAttribPointer(0, 3, GL_FLOAT, 0, sizeof(Vertex), (void*)(offsetof(Vertex, position)));
		m_VertexBuffer.VertexAttribPointer(1, 3, GL_FLOAT, 0, sizeof(Vertex), (void*)(offsetof(Vertex, normals)));
		m_VertexBuffer.VertexAttribIPointer(2, 1, GL_UNSIGNED_INT, sizeof(Vertex), (void*)(offsetof(Vertex, texcoords)));
		m_VertexBuffer.VertexAttribPointer(3, 3, GL_FLOAT, 0, sizeof(Vertex), (void*)(offsetof(Vertex, tangent)));
		m_VertexBuffer.VertexAttribIPointer(4, 1, GL_UNSIGNED_SHORT, sizeof(Vertex), (void*)(offsetof(Vertex, TEXID1)));
		m_VertexBuffer.VertexAttribIPointer(5, 1, GL_UNSIGNED_SHORT, sizeof(Vertex), (void*)(offsetof(Vertex, TEXID2)));

		m_VertexArray.Unbind();
	}

	void Mesh::Buffer()
	{
		if (m_Vertices.size() > 0)
		{
			m_VertexCount = m_Vertices.size();
			m_VertexBuffer.BufferData(m_Vertices.size() * sizeof(Vertex), &m_Vertices.front(), GL_STATIC_DRAW);
			m_Vertices.clear();
		}

		if (m_Indices.size() > 0)
		{
			m_IndicesCount = m_Indices.size();
			m_IndexBuffer.BufferData(m_Indices.size() * sizeof(GLuint), &m_Indices.front(), GL_STATIC_DRAW);
			m_Indexed = true;
			m_Indices.clear();
		}

		else
		{
			m_Indexed = false;
		}
	}
}