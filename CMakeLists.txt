cmake_minimum_required(VERSION 3.21)
project(orbit VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

option(ORBIT_LAYER_SHELL "Use LayerShellQt on Wayland when it is found" ON)
option(ORBIT_INSTALL_QML_MODULE "Also install the Orbit QML module for quickshell configs" ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick Network Sql)
qt_standard_project_setup()

if(ORBIT_LAYER_SHELL)
    find_package(LayerShellQt 6 QUIET)
endif()

qt_add_executable(orbit
    src/main.cpp
    src/backend.cpp src/backend.h
    src/commands.cpp src/commands.h
    src/desktopentries.cpp src/desktopentries.h
    src/host.cpp src/host.h
    src/icons.cpp src/icons.h
)

target_compile_definitions(orbit PRIVATE
    ORBIT_VERSION="${PROJECT_VERSION}"
    QT_PLUGINS_DIR="${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}"
)
# Plain shared-Qt build: nothing to link from the QML imports (and the plugin
# files in Orbit/ import quickshell, which the scanner would chase)
set_target_properties(orbit PROPERTIES QT_QML_MODULE_NO_IMPORT_SCAN TRUE)
target_link_libraries(orbit PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network Qt6::Sql)

if(LayerShellQt_FOUND)
    message(STATUS "orbit: LayerShellQt ${LayerShellQt_VERSION} found, using layer-shell on Wayland")
    target_link_libraries(orbit PRIVATE LayerShellQt::Interface)
    target_compile_definitions(orbit PRIVATE ORBIT_HAVE_LAYER_SHELL)
    if(LayerShellQt_VERSION VERSION_GREATER_EQUAL 6.6)
        target_compile_definitions(orbit PRIVATE ORBIT_LAYER_SHELL_ACTIVE_SCREEN=1)
    else()
        target_compile_definitions(orbit PRIVATE ORBIT_LAYER_SHELL_ACTIVE_SCREEN=0)
    endif()
else()
    message(STATUS "orbit: LayerShellQt not found, the launcher is a plain window")
endif()

# Everything the binary needs is built in: QML, planets, font, default config
file(GLOB_RECURSE ORBIT_MODULE_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
    Orbit/*.qml Orbit/qmldir Orbit/internal/*.js Orbit/planets/* Orbit/fonts/*.ttf)
# The quickshell-only files stay out of the binary
list(REMOVE_ITEM ORBIT_MODULE_FILES Orbit/OrbitWindow.qml Orbit/QuickshellBackend.qml)
set_source_files_properties(src/Main.qml PROPERTIES QT_RESOURCE_ALIAS Main.qml)
set_source_files_properties(config/orbit.conf PROPERTIES QT_RESOURCE_ALIAS orbit.conf)
qt_add_resources(orbit orbit_qml PREFIX /orbit FILES src/Main.qml config/orbit.conf)
qt_add_resources(orbit orbit_module PREFIX /orbit FILES ${ORBIT_MODULE_FILES})

include(GNUInstallDirs)
install(TARGETS orbit RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES config/orbit.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/orbit)
if(ORBIT_INSTALL_QML_MODULE)
    install(DIRECTORY Orbit DESTINATION ${CMAKE_INSTALL_DATADIR}/orbit)
endif()
