package engine

import "core:c/libc"
import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

Float_16 :: struct {
    v: [16]libc.float,
}

// https://github.com/raysan5/raylib/blob/df849d2fb0c7df6a818f2f79dd8343565dd1274c/src/rmodels.c#L130
MAX_MATERIAL_MAPS :: 12

draw_mesh_instanced :: proc(mesh: rl.Mesh, material: rl.Material, instanceTransforms: [^]Float_16, instances: int) {
    // Instancing required variables
    instancesVboId: u32 = 0

    // Bind shader program
    rlgl.EnableShader(material.shader.id)

    // Send required data to shader (matrices, values)
    //-----------------------------------------------------
    // Upload to shader material.colDiffuse
    if (material.shader.locs[rl.ShaderLocationIndex.MAP_ALBEDO] != -1) {
        values: [4]f32 = {
            f32(material.maps[rl.ShaderLocationIndex.MAP_ALBEDO].color.r) / 255.0,
            f32(material.maps[rl.ShaderLocationIndex.MAP_ALBEDO].color.g) / 255.0,
            f32(material.maps[rl.ShaderLocationIndex.MAP_ALBEDO].color.b) / 255.0,
            f32(material.maps[rl.ShaderLocationIndex.MAP_ALBEDO].color.a) / 255.0,
        }

        rlgl.SetUniform(
            material.shader.locs[rl.ShaderLocationIndex.MAP_ALBEDO],
            &values,
            libc.int(rl.ShaderUniformDataType.VEC4),
            1,
        )
    }

    // Upload to shader material.colSpecular (if location available)
    if (material.shader.locs[rl.ShaderLocationIndex.COLOR_SPECULAR] != -1) {
        values: [4]f32 = {
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.r) / 255.0,
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.g) / 255.0,
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.b) / 255.0,
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.a) / 255.0,
        }

        rlgl.SetUniform(
            material.shader.locs[rl.ShaderLocationIndex.COLOR_SPECULAR],
            &values,
            libc.int(rl.ShaderUniformDataType.VEC4),
            1,
        )
    }

    // Get a copy of current matrices to work with,
    // just in case stereo render is required, and we need to modify them
    // NOTE: At this point the modelview matrix just contains the view matrix (camera)
    // That's because BeginMode3D() sets it and there is no model-drawing function
    // that modifies it, all use rlPushMatrix() and rlPopMatrix()
    matModel := rl.Matrix(1)
    matView := rlgl.GetMatrixModelview()
    matModelView := rl.Matrix(1)
    matProjection := rlgl.GetMatrixProjection()

    // Upload view and projection matrices (if locations available)
    if (material.shader.locs[rl.ShaderLocationIndex.MATRIX_VIEW] != -1) {
        rlgl.SetUniformMatrix(material.shader.locs[rl.ShaderLocationIndex.MATRIX_VIEW], matView)
    }
    if (material.shader.locs[rl.ShaderLocationIndex.MATRIX_PROJECTION] != -1) {
        rlgl.SetUniformMatrix(material.shader.locs[rl.ShaderLocationIndex.MATRIX_PROJECTION], matProjection)
    }

    // Enable mesh VAO to attach new buffer
    rlgl.EnableVertexArray(mesh.vaoId)

    // This could alternatively use a static VBO and either glMapBuffer() or glBufferSubData()
    // It isn't clear which would be reliably faster in all cases and on all platforms,
    // anecdotally glMapBuffer() seems very slow (syncs) while glBufferSubData() seems
    // no faster, since we're transferring all the transform matrices anyway
    size := libc.int(instances * size_of(Float_16))
    fmt.println(size)

    instancesVboId = rlgl.LoadVertexBuffer(instanceTransforms, size, false)

    // Instances transformation matrices are send to shader attribute location: SHADER_LOC_MATRIX_MODEL
    for i: u32 = 0; i < 4; i += 1 {
        rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL]) + i)
        offset := libc.int(i) * size_of(rl.Vector4)
        rlgl.SetVertexAttribute(
            libc.uint(material.shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL]) + i,
            4,
            rlgl.FLOAT,
            false,
            size_of(rl.Matrix),
            &offset,
        )
        rlgl.SetVertexAttributeDivisor(libc.uint(material.shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL]) + i, 1)
    }

    rlgl.DisableVertexBuffer()
    rlgl.DisableVertexArray()

    // Accumulate internal matrix transform (push/pop) and view matrix
    // NOTE: In this case, model instance transformation must be computed in the shader
    matModelView = rlgl.GetMatrixTransform() * matView

    // Upload model normal matrix (if locations available)
    if (material.shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL] != -1) {
        //mat := linalg.inverse_transpose(matModel)
        rlgl.SetUniformMatrix(
            material.shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL],
            rl.MatrixTranspose(rl.MatrixInvert(matModel)),
        )
    }
    //-----------------------------------------------------

    // Bind active texture maps (if available)
    index: int = 0
    for ; index < MAX_MATERIAL_MAPS; index += 1 {
        if material.maps[index].texture.id > 0 {
            // Select current shader texture slot
            rlgl.ActiveTextureSlot(libc.int(index))

            // Enable texture for active slot
            if ((index == int(rl.MaterialMapIndex.IRRADIANCE)) ||
                   (index == int(rl.MaterialMapIndex.PREFILTER)) ||
                   (index == int(rl.MaterialMapIndex.CUBEMAP))) {
                rlgl.EnableTextureCubemap(material.maps[index].texture.id)
            } else {
                rlgl.EnableTexture(material.maps[index].texture.id)
            }

            rlgl.SetUniform(
                material.shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO) + index],
                &index,
                libc.int(rl.ShaderUniformDataType.INT),
                1,
            )
        }
    }

    // Try binding vertex array objects (VAO)
    // or use VBOs if not possible
    if (!rlgl.EnableVertexArray(mesh.vaoId)) {
        zero_offset := 0

        // Bind mesh VBO data: vertex position (shader-location = 0)
        rlgl.EnableVertexBuffer(mesh.vboId[0])
        rlgl.SetVertexAttribute(
            libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_POSITION]),
            3,
            rlgl.FLOAT,
            false,
            0,
            &zero_offset,
        )
        rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_POSITION]))

        // Bind mesh VBO data: vertex texcoords (shader-location = 1)
        rlgl.EnableVertexBuffer(mesh.vboId[1])
        rlgl.SetVertexAttribute(
            libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_TEXCOORD01]),
            2,
            rlgl.FLOAT,
            false,
            0,
            &zero_offset,
        )
        rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_TEXCOORD01]))

        if material.shader.locs[rl.ShaderLocationIndex.VERTEX_NORMAL] != -1 {
            // Bind mesh VBO data: vertex normals (shader-location = 2)
            rlgl.EnableVertexBuffer(mesh.vboId[2])
            rlgl.SetVertexAttribute(
                libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_NORMAL]),
                3,
                rlgl.FLOAT,
                false,
                0,
                &zero_offset,
            )
            rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_NORMAL]))
        }

        // Bind mesh VBO data: vertex colors (shader-location = 3, if available)
        if material.shader.locs[rl.ShaderLocationIndex.VERTEX_COLOR] != -1 {
            if mesh.vboId[3] != 0 {
                rlgl.EnableVertexBuffer(mesh.vboId[3])
                rlgl.SetVertexAttribute(
                    libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_COLOR]),
                    4,
                    rlgl.UNSIGNED_BYTE,
                    true,
                    0,
                    &zero_offset,
                )
                rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_COLOR]))
            } else {
                // Set default value for unused attribute
                // NOTE: Required when using default shader and no VAO support
                value: [4]f32 = {1.0, 1.0, 1.0, 1.0}
                rlgl.SetVertexAttributeDefault(
                    material.shader.locs[rl.ShaderLocationIndex.VERTEX_COLOR],
                    &value,
                    libc.int(rlgl.ShaderAttributeDataType.VEC4),
                    4,
                )
                rlgl.DisableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_COLOR]))
            }
        }

        // Bind mesh VBO data: vertex tangents (shader-location = 4, if available)
        if material.shader.locs[rl.ShaderLocationIndex.VERTEX_TANGENT] != -1 {
            rlgl.EnableVertexBuffer(mesh.vboId[4])
            rlgl.SetVertexAttribute(
                libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_TANGENT]),
                4,
                rlgl.FLOAT,
                false,
                0,
                &zero_offset,
            )
            rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_TANGENT]))
        }

        // Bind mesh VBO data: vertex texcoords2 (shader-location = 5, if available)
        if material.shader.locs[rl.ShaderLocationIndex.VERTEX_TEXCOORD02] != -1 {
            rlgl.EnableVertexBuffer(mesh.vboId[5])
            rlgl.SetVertexAttribute(
                libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_TEXCOORD02]),
                2,
                rlgl.FLOAT,
                false,
                0,
                &zero_offset,
            )
            rlgl.EnableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_TEXCOORD02]))
        }

        if (mesh.indices != nil) do rlgl.EnableVertexBufferElement(mesh.vboId[6])
    }

    // WARNING: Disable vertex attribute color input if mesh can not provide that data (despite location being enabled in shader)
    if mesh.vboId[3] == 0 do rlgl.DisableVertexAttribute(libc.uint(material.shader.locs[rl.ShaderLocationIndex.VERTEX_COLOR]))

    eyeCount: libc.int = 1
    if (rlgl.IsStereoRenderEnabled()) do eyeCount = 2

    for eye: libc.int = 0; eye < eyeCount; eye += 1 {
        // Calculate model-view-projection matrix (MVP)
        matModelViewProjection := rl.Matrix(1)
        if eyeCount == 1 {
            matModelViewProjection = matModelView * matProjection
        } else {
            // Setup current eye viewport (half screen width)
            rlgl.Viewport(eye * rlgl.GetFramebufferWidth() / 2, 0, rlgl.GetFramebufferWidth() / 2, rlgl.GetFramebufferHeight())
            matModelViewProjection = (matModelView * rlgl.GetMatrixViewOffsetStereo(eye)) * rlgl.GetMatrixProjectionStereo(eye)
        }

        // Send combined model-view-projection matrix to shader
        rlgl.SetUniformMatrix(material.shader.locs[rl.ShaderLocationIndex.MATRIX_MVP], matModelViewProjection)

        // Draw mesh instanced
        if mesh.indices != nil {
            rlgl.DrawVertexArrayElementsInstanced(0, mesh.triangleCount * 3, nil, libc.int(instances))
        } else {
            rlgl.DrawVertexArrayInstanced(0, mesh.vertexCount, libc.int(instances))
        }
    }

    // Unbind all bound texture maps
    for mat_i: libc.int = 0; mat_i < MAX_MATERIAL_MAPS; mat_i += 1 {
        if material.maps[mat_i].texture.id > 0 {
            // Select current shader texture slot
            rlgl.ActiveTextureSlot(mat_i)

            // Disable texture for active slot
            if ((mat_i == libc.int(rl.MaterialMapIndex.IRRADIANCE)) ||
                   (mat_i == libc.int(rl.MaterialMapIndex.PREFILTER)) ||
                   (mat_i == libc.int(rl.MaterialMapIndex.CUBEMAP))) {
                rlgl.DisableTextureCubemap()
            } else {
                rlgl.DisableTexture()
            }
        }
    }

    // Disable all possible vertex array objects (or VBOs)
    rlgl.DisableVertexArray()
    rlgl.DisableVertexBuffer()
    rlgl.DisableVertexBufferElement()

    // Disable shader program
    rlgl.DisableShader()

    // Remove instance transforms buffer
    rlgl.UnloadVertexBuffer(instancesVboId)
}
