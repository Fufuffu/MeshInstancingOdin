package main

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import "core:os"

given_dll_name: string

main :: proc() {
    if len(os.args) != 2 {
        fmt.eprintln("Usage: main dll_name")
        os.exit(1)
    }
    given_dll_name = os.args[1]

    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    print_mem_leaks :: proc(alloc: ^mem.Tracking_Allocator) -> bool {
        leaks := false

        for _, leak in alloc.allocation_map {
            fmt.printf("ERROR: %v leaked memory: %m\n", leak.location, leak.size)
            leaks = true
        }
        for bad_free in alloc.bad_free_array {
            fmt.printf("ERROR: %v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
            leaks = true
        }

        mem.tracking_allocator_clear(alloc)
        return leaks
    }

    game_api_version := 0
    game_api, game_api_ok := load_game_api(game_api_version)

    if !game_api_ok {
        fmt.println("Failed to load API")
        return
    }

    game_api_version += 1

    game_api.init_window()
    game_api.init()

    for {
        if game_api.update() == false {
            break
        }

        dll_time, dll_time_err := os.last_write_time_by_name(
            fmt.aprintf("%s.dll", given_dll_name, allocator = context.temp_allocator),
        )

        reload := (dll_time_err == os.ERROR_NONE && game_api.dll_time != dll_time)

        if reload {
            new_api, new_api_ok := load_game_api(game_api_version)
            if new_api_ok {
                // Do not reset allocator just clear, game mem will always "leak"
                mem.tracking_allocator_clear(&tracking_allocator)
                game_memory := game_api.memory()
                unload_game_api(game_api)
                game_api = new_api
                game_api.hot_reloaded(game_memory)

                game_api_version += 1
            }
        }

        free_all(context.temp_allocator)
    }

    free_all(context.temp_allocator)
    game_api.shutdown()
    print_mem_leaks(&tracking_allocator)
    game_api.shutdown_window()
    unload_game_api(game_api)
    mem.tracking_allocator_destroy(&tracking_allocator)
}

GameAPI :: struct {
    init:            proc(),
    init_window:     proc(),
    update:          proc() -> bool,
    shutdown:        proc(),
    shutdown_window: proc(),
    memory:          proc() -> rawptr,
    hot_reloaded:    proc(_: rawptr),
    lib:             dynlib.Library,
    dll_time:        os.File_Time,
    api_version:     int,
}

load_game_api :: proc(api_version: int) -> (GameAPI, bool) {
    dll_time, dll_time_err := os.last_write_time_by_name(
        fmt.aprintf("%s.dll", given_dll_name, allocator = context.temp_allocator),
    )

    if dll_time_err != os.ERROR_NONE {
        fmt.printf("Could not fetch last write date of %s.dll\n", given_dll_name)
        return {}, false
    }

    dll_name := fmt.tprintf("{0}_{1}.dll", given_dll_name, api_version)

    copy_cmd := fmt.ctprintf("copy {0}.dll {1}", given_dll_name, dll_name)
    if libc.system(copy_cmd) != 0 {
        fmt.printf("Failed to copy {0}.dll to {1}\n", given_dll_name, dll_name)
        return {}, false
    }

    lib, lib_ok := dynlib.load_library(dll_name)

    if !lib_ok {
        fmt.println("Failed loading DLL", given_dll_name)
        return {}, false
    }

    api := GameAPI {
        init            = cast(proc())(dynlib.symbol_address(lib, "game_init") or_else nil),
        init_window     = cast(proc())(dynlib.symbol_address(lib, "game_init_window") or_else nil),
        update          = cast(proc() -> bool)(dynlib.symbol_address(lib, "game_update") or_else nil),
        shutdown        = cast(proc())(dynlib.symbol_address(lib, "game_shutdown") or_else nil),
        shutdown_window = cast(proc())(dynlib.symbol_address(lib, "game_shutdown_window") or_else nil),
        memory          = cast(proc() -> rawptr)(dynlib.symbol_address(lib, "get_game_memory") or_else nil),
        hot_reloaded    = cast(proc(_: rawptr))(dynlib.symbol_address(lib, "game_hot_reloaded") or_else nil),
        lib             = lib,
        dll_time        = dll_time,
        api_version     = api_version,
    }

    if api.init == nil ||
       api.init_window == nil ||
       api.update == nil ||
       api.shutdown == nil ||
       api.shutdown_window == nil ||
       api.memory == nil ||
       api.hot_reloaded == nil {
        dynlib.unload_library(api.lib)
        fmt.println("DLL missing required procedures: ", given_dll_name)
        return {}, false
    }

    return api, true
}

unload_game_api :: proc(api: GameAPI) {
    if api.lib != nil {
        dynlib.unload_library(api.lib)
    }

    del_cmd := fmt.ctprintf("del {0}_{1}.dll", given_dll_name, api.api_version)
    if libc.system(del_cmd) != 0 {
        fmt.printf("Failed to remove {0}_{1}.dll copy\n", given_dll_name, api.api_version)
    }
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1