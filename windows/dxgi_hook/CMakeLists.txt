cmake_minimum_required(VERSION 3.14)
project(dxgi_hook LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(dxgi_hook SHARED
    "dxgi_hook.h"
    "dxgi_hook.cpp"
    "dxgi.def"
    "minhook/MinHook.h"
    "minhook/buffer.h"
    "minhook/buffer.c"
    "minhook/hde64.h"
    "minhook/hde64.c"
    "minhook/hook.c"
    "minhook/pstdint.h"
    "minhook/table64.h"
    "minhook/trampoline.h"
    "minhook/trampoline.c"
)

target_include_directories(dxgi_hook PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/minhook"
)

target_compile_definitions(dxgi_hook PRIVATE
    "DXGI_HOOK_EXPORTS"
    "NOMINMAX"
    "UNICODE"
    "_UNICODE"
)

target_link_libraries(dxgi_hook PRIVATE
    "dxgi.lib"
    "d3d11.lib"
    "shlwapi.lib"
    "user32.lib"
    "kernel32.lib"
)

# Output dxgi_hook.dll into bin/ directory as well
set_target_properties(dxgi_hook PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/../bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/../bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_SOURCE_DIR}/../bin"
)
