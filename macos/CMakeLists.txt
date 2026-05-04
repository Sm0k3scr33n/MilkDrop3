cmake_minimum_required(VERSION 3.20)
project(MilkDrop3 VERSION 3.0 LANGUAGES CXX OBJCXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)

# ── Dependencies ─────────────────────────────────────────────────────────────
find_package(SDL2 REQUIRED)

# GLM (header-only math library – replaces D3DX math)
find_package(glm QUIET)
if(NOT glm_FOUND)
    include(FetchContent)
    FetchContent_Declare(glm
        GIT_REPOSITORY https://github.com/g-truc/glm.git
        GIT_TAG        1.0.1)
    FetchContent_MakeAvailable(glm)
endif()

# ── Source files ─────────────────────────────────────────────────────────────
set(PLATFORM_SOURCES
    platform/ini_parser.cpp
)

set(RENDER_SOURCES
    render/MetalDevice.mm
    render/MetalTexture.mm
    render/MetalShader.mm
    render/HLSLToMSL.mm
)

set(AUDIO_SOURCES
    audio/CoreAudioCapture.mm
)

set(APP_SOURCES
    app/main.mm
    app/AppDelegate.mm
)

# Original vis_milk2 sources (platform-agnostic logic only)
set(VIS_SOURCES
    ../code/vis_milk2/fft.cpp
    ../code/vis_milk2/state.cpp
    ../code/vis_milk2/menu.cpp
    ../code/vis_milk2/utility.cpp
    ../code/vis_milk2/support.cpp
    ../code/vis_milk2/texmgr.cpp
    ../code/vis_milk2/textmgr.cpp
    ../code/vis_milk2/plugin.cpp
    ../code/vis_milk2/pluginshell.cpp
    ../code/vis_milk2/dxcontext.cpp
    ../code/vis_milk2/milkdropfs.cpp
    ../code/vis_milk2/wasabi.cpp
)

# ns-eel2 expression evaluator (mostly portable C)
set(NSEEL_SOURCES
    ../code/ns-eel2/nseel-caltab.c
    ../code/ns-eel2/nseel-cfunc.c
    ../code/ns-eel2/nseel-compiler.c
    ../code/ns-eel2/nseel-eval.c
    ../code/ns-eel2/nseel-lextab.c
    ../code/ns-eel2/nseel-ram.c
    ../code/ns-eel2/nseel-yylex.c
)

# ── Executable target ─────────────────────────────────────────────────────────
add_executable(MilkDrop3
    ${PLATFORM_SOURCES}
    ${RENDER_SOURCES}
    ${AUDIO_SOURCES}
    ${APP_SOURCES}
    ${VIS_SOURCES}
    ${NSEEL_SOURCES}
)

# ── Metal shader compilation ──────────────────────────────────────────────────
# Compile our base .metal file into a .metallib at build time
set(METAL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/render/shaders/milkdrop_base.metal")
set(METAL_LIB "${CMAKE_CURRENT_BINARY_DIR}/milkdrop_base.metallib")

add_custom_command(
    OUTPUT  ${METAL_LIB}
    COMMAND xcrun -sdk macosx metal -c ${METAL_SRC} -o ${CMAKE_CURRENT_BINARY_DIR}/milkdrop_base.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/milkdrop_base.air -o ${METAL_LIB}
    DEPENDS ${METAL_SRC}
    COMMENT "Compiling Metal shaders"
)
add_custom_target(MetalShaders DEPENDS ${METAL_LIB})
add_dependencies(MilkDrop3 MetalShaders)

# Copy metallib next to the binary
add_custom_command(TARGET MilkDrop3 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${METAL_LIB}
        $<TARGET_FILE_DIR:MilkDrop3>/milkdrop_base.metallib
)

# ── Include paths ─────────────────────────────────────────────────────────────
target_include_directories(MilkDrop3 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}              # macos/
    ${CMAKE_CURRENT_SOURCE_DIR}/platform
    ${CMAKE_CURRENT_SOURCE_DIR}/render
    ${CMAKE_CURRENT_SOURCE_DIR}/audio
    ${CMAKE_CURRENT_SOURCE_DIR}/app
    ../code/vis_milk2
    ../code/ns-eel2
    ../code/audio
    ${SDL2_INCLUDE_DIRS}
)

# ── Compile definitions ───────────────────────────────────────────────────────
target_compile_definitions(MilkDrop3 PRIVATE
    MILKDROP_MACOS=1          # gate all Mac-specific code
    GL_SILENCE_DEPRECATION=1  # suppress deprecated OpenGL warnings if any slip in
)

# ── Frameworks & libraries ────────────────────────────────────────────────────
target_link_libraries(MilkDrop3 PRIVATE
    ${SDL2_LIBRARIES}
    glm::glm
    "-framework Metal"
    "-framework MetalKit"
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AudioUnit"
    "-framework AVFoundation"
    "-framework Foundation"
    "-framework Cocoa"
    "-framework QuartzCore"
    "-framework CoreGraphics"
    "-framework CoreText"
)

# ── macOS deployment target ───────────────────────────────────────────────────
set_target_properties(MilkDrop3 PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "MilkDrop3"
    MACOSX_BUNDLE_BUNDLE_VERSION "3.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "3.0"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/app/Info.plist.in"
    XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET "13.0"
)
