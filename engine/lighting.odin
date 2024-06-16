package engine

import "core:c/libc"
import rl "vendor:raylib"

// Config constants
MAX_LIGHTS :: 2

Light :: struct {
    type:        LightType,
    enabled:     bool,
    position:    rl.Vector3,
    target:      rl.Vector3,
    color_hsv:   rl.Vector3,

    // Shader locations
    enabledLoc:  i32,
    typeLoc:     i32,
    positionLoc: i32,
    targetLoc:   i32,
    colorLoc:    i32,
}

LightType :: enum {
    DIRECTIONAL,
    POINT,
}

create_light :: proc(
    light_count: ^i32,
    type: LightType,
    position: rl.Vector3,
    target: rl.Vector3,
    color_hsv: rl.Vector3,
    shader: rl.Shader,
) -> (
    Light,
    bool,
) #optional_ok {
    light: Light = {}

    if light_count^ < MAX_LIGHTS {
        light.enabled = true
        light.type = type
        light.position = position
        light.target = target
        light.color_hsv = color_hsv

        light.enabledLoc = rl.GetShaderLocation(shader, rl.TextFormat("lights[%i].enabled", light_count^))
        light.typeLoc = rl.GetShaderLocation(shader, rl.TextFormat("lights[%i].type", light_count^))
        light.positionLoc = rl.GetShaderLocation(shader, rl.TextFormat("lights[%i].position", light_count^))
        light.targetLoc = rl.GetShaderLocation(shader, rl.TextFormat("lights[%i].target", light_count^))
        light.colorLoc = rl.GetShaderLocation(shader, rl.TextFormat("lights[%i].color", light_count^))

        update_light_values(shader, &light)

        light_count^ = light_count^ + 1
        return light, true
    }

    return light, false
}

update_light_values :: proc(shader: rl.Shader, light: ^Light) {
    // Send to shader light enabled state and type
    rl.SetShaderValue(shader, light.enabledLoc, &light.enabled, .INT)
    rl.SetShaderValue(shader, light.typeLoc, &light.type, .INT)

    // Send to shader light position values
    position: [3]libc.float = {light.position.x, light.position.y, light.position.z}
    rl.SetShaderValue(shader, light.positionLoc, &position, .VEC3)

    // Send to shader light target position values
    target: [3]libc.float = {light.target.x, light.target.y, light.target.z}
    rl.SetShaderValue(shader, light.targetLoc, &target, .VEC3)

    // Send to shader light color values
    rgb_color := rl.ColorFromHSV(light.color_hsv.x, light.color_hsv.y, light.color_hsv.z)
    color: [4]libc.float =  {
        libc.float(rgb_color.r) / libc.float(255),
        libc.float(rgb_color.g) / libc.float(255),
        libc.float(rgb_color.b) / libc.float(255),
        libc.float(rgb_color.a) / libc.float(255),
    }
    rl.SetShaderValue(shader, light.colorLoc, &color, .VEC4)
}
