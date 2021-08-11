#include "MeshOptimizer.h"

#define PACK_U16(lsb, msb) ((uint16_t) ( ((uint16_t)(lsb) & 0xFF) | (((uint16_t)(msb) & 0xFF) << 8) ))

glm::vec4 SampleTexture(char* tex, glm::vec2 uv, int w, int h) 
{
    glm::ivec2 texel = glm::ivec2(glm::floor(uv * glm::vec2(w, h)));
    int idx = texel.x * w + texel.y;

    if (idx + 4 >= w * h * 4) {
        throw "wtf";
    }

    return glm::vec4(tex[idx], tex[idx + 1], tex[idx + 2], tex[idx + 3]);
}

glm::vec4 BilinearInterpolate(char* tex, glm::vec2 uv, int w, int h)
{
    glm::vec2 texSize = glm::vec2(w,h);
    glm::vec2 pos = uv * texSize - 0.5f;
    glm::vec2 f = glm::fract(pos);
    glm::vec2 pos_top_left = glm::floor(pos);
    glm::vec4 tl = SampleTexture(tex, (pos_top_left + glm::vec2(0.5, 0.5)) / texSize, w, h);
    glm::vec4 tr = SampleTexture(tex, (pos_top_left + glm::vec2(1.5, 0.5)) / texSize, w, h);
    glm::vec4 bl = SampleTexture(tex, (pos_top_left + glm::vec2(0.5, 1.5)) / texSize, w, h);
    glm::vec4 br = SampleTexture(tex, (pos_top_left + glm::vec2(1.5, 1.5)) / texSize, w, h);
    glm::vec4 ret = glm::mix(glm::mix(tl, tr, f.x), glm::mix(bl, br, f.x), f.y);
    return ret;
}

void Lumen::SoftwareUpsample(char* pixels, uint8_t type, int w, int h, int nw, int nh)
{
    char* NewTexture = new char[w * h * 4];

    for (int x = 0; x < nw; x++) {
        for (int y = 0; y < nh; y++)
        {
            glm::vec2 uv = glm::vec2(float(x) / float(nw), float(y) / float(nh));

            glm::vec4 colat = BilinearInterpolate(pixels, uv, w, h);
            int r = static_cast<int>(glm::floor(colat.x));
            int g = static_cast<int>(glm::floor(colat.y));
            int b = static_cast<int>(glm::floor(colat.z));
            int a = static_cast<int>(glm::floor(colat.w));

            int idx = x * w + y;
            NewTexture[idx] = r;
            NewTexture[idx+1] = g;
            NewTexture[idx+2] = b;
            NewTexture[idx+3] = a;
        }
    }
}

void Lumen::OptimizeMesh(Object& object)
{
    Mesh OptimizedMesh = Mesh(0);
    int IndexOffset = 0;

    std::vector<std::string> AlbedoPaths;
    std::vector<std::string> NormalPaths;
    std::vector<std::string> RoughnessPaths;
    std::vector<std::string> MetalnessPaths;
    std::vector<std::string> AOPaths;

    for (auto& e : object.m_Meshes)
    {
        AlbedoPaths.push_back(e.TexturePaths[0]);
        NormalPaths.push_back(e.TexturePaths[1]);
        RoughnessPaths.push_back(e.TexturePaths[2]);
        MetalnessPaths.push_back(e.TexturePaths[3]);
        AOPaths.push_back(e.TexturePaths[4]);
    }

    OptimizedMesh.m_AlbedoMap.CreateArray(AlbedoPaths, { 1024, 1024 }, true, true);
    OptimizedMesh.m_NormalMap.CreateArray(NormalPaths, { 1024, 1024 }, true, true);
    OptimizedMesh.m_RoughnessMap.CreateArray(RoughnessPaths, { 1024, 1024 }, true, true);
    OptimizedMesh.m_MetalnessMap.CreateArray(MetalnessPaths, { 1024, 1024 }, true, true);
    OptimizedMesh.m_AmbientOcclusionMap.CreateArray(AOPaths, { 1024, 1024 }, true, true);

    for (auto& e : object.m_Meshes)
    {
        // set texture ids
        for (int t = 0; t < e.m_Vertices.size(); t++)
        {
            Vertex& vertex = e.m_Vertices[t];
            uint8_t albedo_id = OptimizedMesh.m_AlbedoMap.GetTexture(e.TexturePaths[0]);
            uint8_t normal_id = OptimizedMesh.m_NormalMap.GetTexture(e.TexturePaths[1]);
            uint8_t roughness_id = OptimizedMesh.m_RoughnessMap.GetTexture(e.TexturePaths[2]);
            uint8_t metalness_id = OptimizedMesh.m_MetalnessMap.GetTexture(e.TexturePaths[3]);
            uint16_t Data1 = PACK_U16(albedo_id, normal_id);
            uint16_t Data2 = PACK_U16(roughness_id, metalness_id);
            vertex.TEXID1 = Data1;
            vertex.TEXID2 = Data2;
        }

        OptimizedMesh.m_Vertices.insert(std::end(OptimizedMesh.m_Vertices), std::begin(e.m_Vertices), std::end(e.m_Vertices));

        for (int i = 0; i < e.m_Indices.size(); i++) {

            int index = e.m_Indices.at(i);
            OptimizedMesh.m_Indices.push_back(index + IndexOffset);
        }
    
        IndexOffset += e.m_Vertices.size();
    }

    object.m_Meshes.clear();
    object.m_Meshes.push_back(std::move(OptimizedMesh));
}

