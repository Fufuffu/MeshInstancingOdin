package engine

import "core:math"
import "core:mem"
import "core:strings"
import rl "vendor:raylib"


@(require_results)
to_cstring_temp :: proc(str: string) -> cstring {
    return strings.clone_to_cstring(str, allocator = context.temp_allocator)
}

@(require_results)
allocate_cstring :: proc(
    size: int,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    res: cstring,
    err: mem.Allocator_Error,
) #optional_allocator_error {
    c := make([]byte, size + 1, allocator, loc) or_return
    c[0] = 0
    return cstring(&c[0]), nil
}

copy_into_cstring :: proc(str: string, cstr: ^cstring, max_size: int) {
    assert(len(str) < max_size, "String is larger than buffer size")
    bytes := transmute([^]u8)cstr^

    for i in 0 ..< len(str) {
        bytes[i] = str[i]
    }
    bytes[len(str)] = 0
}

@(require_results)
color_from_vec_hsv :: proc "contextless" (hsv: rl.Vector3) -> rl.Color {
    return rl.ColorFromHSV(hsv.x, hsv.y, hsv.z)
}