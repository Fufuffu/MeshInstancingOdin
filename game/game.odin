package game

import en "../engine"
import "core:c/libc"
import "core:fmt"
import rl "vendor:raylib"

DEV_BUILD :: #config(DEV_BUILD, false)

MAX_INSTANCES :: 10000

GameMemory :: struct {
    delta_time_scale: f32,
    cube_mesh:        rl.Mesh,
    //transforms:       [MAX_INSTANCES]en.Float_16,
    transforms:       [MAX_INSTANCES]rl.Matrix,
    shader:           rl.Shader,
    lights:           [en.MAX_LIGHTS]en.Light,
    light_count:      i32,
    mat_instanced:    rl.Material,
    mat_default:      rl.Material,
}

game_memory: ^GameMemory

SCREEN_WIDTH: i32 = 1792
SCREEN_HEIGHT: i32 = 1008

camera: rl.Camera3D = {
    position   = rl.Vector3{-125, 125, -125},
    target     = rl.Vector3(0),
    up         = rl.Vector3{0, 1, 0},
    fovy       = 45,
    projection = rl.CameraProjection.PERSPECTIVE,
}

@(export)
game_init_window :: proc() {
    rl.SetConfigFlags({.MSAA_4X_HINT})
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "MeshInstancing")
}

@(export)
game_init :: proc() {
    rl.SetExitKey(.KEY_NULL)

    // Init game state
    game_memory = new(GameMemory)
    game_memory.delta_time_scale = 1

    // Define mesh to be instanced
    game_memory.cube_mesh = rl.GenMeshCube(1, 1, 1)

    // Init all matrices
    for i in 0 ..< MAX_INSTANCES {
        translation := rl.MatrixTranslate(
            f32(rl.GetRandomValue(-100, 100)),
            f32(rl.GetRandomValue(-100, 100)),
            f32(rl.GetRandomValue(-100, 100)),
        )
        axis := rl.Vector3Normalize(
            rl.Vector3{f32(rl.GetRandomValue(0, 360)), f32(rl.GetRandomValue(0, 360)), f32(rl.GetRandomValue(0, 360))},
        )
        angle := f32(rl.GetRandomValue(0, 10)) * rl.DEG2RAD
        rotation := rl.MatrixRotate(axis, angle)

        //game_memory.transforms[i] = en.Float_16{rl.MatrixToFloatV(rotation * translation)}
        game_memory.transforms[i] = rotation * translation
    }

    // Load instanced lighting shaders
    game_memory.shader = rl.LoadShader("resources/shaders/lighting_instancing.vs", "resources/shaders/lighting.fs")

    // Get shader locations
    game_memory.shader.locs[rl.ShaderLocationIndex.MATRIX_MVP] = rl.GetShaderLocation(game_memory.shader, "mvp")
    game_memory.shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW] = rl.GetShaderLocation(game_memory.shader, "viewPos")
    game_memory.shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocationAttrib(
        game_memory.shader,
        "instanceTransform",
    )

    // Set shader value: ambient light level
    ambientLoc := rl.GetShaderLocation(game_memory.shader, "ambient")
    ambientValue: [4]libc.float = {libc.float(0.2), libc.float(0.2), libc.float(0.2), libc.float(1)}
    rl.SetShaderValue(game_memory.shader, ambientLoc, &ambientValue, .VEC4)

    game_memory.lights[game_memory.light_count] = en.create_light(
        &game_memory.light_count,
        .DIRECTIONAL,
        rl.Vector3{50, 50, 0},
        rl.Vector3(0),
        rl.Vector3{360, 1, 1},
        game_memory.shader,
    )

    // NOTE: We are assigning the intancing shader to material.shader
    // to be used on mesh drawing with DrawMeshInstanced()
    game_memory.mat_instanced = rl.LoadMaterialDefault()
    game_memory.mat_instanced.shader = game_memory.shader
    game_memory.mat_instanced.maps[rl.MaterialMapIndex.ALBEDO].color = rl.RED

    // Load default material (using raylib intenral default shader) for non-instanced mesh drawing
    // WARNING: Default shader enables vertex color attribute BUT GenMeshCube() does not generate vertex colors, so,
    // when drawing the color attribute is disabled and a default color value is provided as input for thevertex attribute
    game_memory.mat_default = rl.LoadMaterialDefault()
    game_memory.mat_default.maps[rl.MaterialMapIndex.ALBEDO].color = rl.BLUE

    rl.SetTargetFPS(60)
}

@(export)
game_update :: proc() -> bool {
    unscaled_delta_time := rl.GetFrameTime()
    scaled_delta_time := game_memory.delta_time_scale * unscaled_delta_time

    // Update game
    rl.UpdateCamera(&camera, rl.CameraMode.ORBITAL)
    cameraPos := rl.Vector3{camera.position.x, camera.position.y, camera.position.z}
    rl.SetShaderValue(game_memory.shader, game_memory.shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW], &cameraPos, .VEC3)

    // Draw game
    game_draw()

    return !rl.WindowShouldClose()
}

game_draw :: proc() {
    rl.BeginDrawing()
    defer rl.EndDrawing()

    rl.ClearBackground(rl.WHITE)

    rl.BeginMode3D(camera)
    rl.DrawMesh(game_memory.cube_mesh, game_memory.mat_default, rl.MatrixTranslate(-10, 0, 0))
    rl.DrawMeshInstanced(game_memory.cube_mesh, game_memory.mat_instanced, raw_data(&game_memory.transforms), MAX_INSTANCES)
    rl.DrawMesh(game_memory.cube_mesh, game_memory.mat_default, rl.MatrixTranslate(10, 0, 0))
    rl.EndMode3D()

    rl.DrawFPS(10, 10)
}

@(export)
game_shutdown :: proc() {
    free(game_memory)
}

@(export)
game_shutdown_window :: proc() {
    rl.CloseWindow()
}

@(export)
get_game_memory :: proc() -> rawptr {
    return game_memory
}

@(export)
game_hot_reloaded :: proc(mem: ^GameMemory) {
    game_memory = mem
}
