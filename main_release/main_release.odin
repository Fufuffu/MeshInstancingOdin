package main_release

import "../game"

main :: proc() {
    game.game_init_window()
    game.game_init()

    for {
        if game.game_update() == false {
            break
        }

        free_all(context.temp_allocator)
    }

    free_all(context.temp_allocator)
    game.game_shutdown()
    game.game_shutdown_window()
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
