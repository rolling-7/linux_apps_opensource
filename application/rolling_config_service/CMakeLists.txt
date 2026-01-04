#/* This program is free software; you can redistribute it and/or modify
# * it under the terms of the GNU Lesser General Public License as published by
# * the Free Software Foundation; either version 2 of the License, or
# * (at your option) any later version.
# *
# * This program is distributed in the hope that it will be useful,
# * but WITHOUT ANY WARRANTY; without even the implied warranty of
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# * GNU Lesser General Public License for more details.
# *
# * You should have received a copy of the GNU Lesser General Public License
# * along with this program. If not, see <http://www.gnu.org/licenses/>.
# *
# * Copyright (C) 2025, Rolling Wireless S.a.r.l.
# */

cmake_minimum_required(VERSION 3.6)
project(rolling_config_service)

# Version configuration
set(CONFIG_MAJOR_VERSION 2)
set(CONFIG_MINOR_VERSION 0)
set(CONFIG_PATCH_VERSION 10)
set(CONFIG_VERSION_STRING ${CONFIG_MAJOR_VERSION}.${CONFIG_MINOR_VERSION}.${CONFIG_PATCH_VERSION})
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/version.h.in"
		"./version.h")

# Compilation options setting
set(CMAKE_C_COMPILER gcc)
set(CONFIG_PREPROCESSOR_DEF "-fstack-protector-strong -O2 -Wformat -Wformat-security  -fPIC -std=gnu99")
add_compile_options(-pthread)

set(build_by_code 1)

# When BUILD_LIB is yes, automatically set build_by_code to 1
if(${BUILD_LIB} STREQUAL "yes")
    set(build_by_code 1)
    message(STATUS "Build lib mode enabled, setting build_by_code=1")
else()
    message(STATUS "Build exe mode enabled, setting build_by_code=0")
    # Only in non-BUILD_LIB mode, when build_by_lib is 1, set BUILD_LIB to no
    if(build_by_lib)
        set(build_by_code 0)
        set(BUILD_LIB "no")
        message(STATUS "Build by lib mode enabled, setting BUILD_LIB=no")
    endif()
endif()

# Dependency lookup
find_package(LibXml2 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0 gio-unix-2.0)

# Add preprocessor definitions
add_definitions(${CONFIG_PREPROCESSOR_DEF})

# Define common link library variables
set(CONFIG_COMMON_LIBS
    ${PROJECT_BINARY_DIR}/../3rd/iniparser/libiniparser.a
    LibXml2::LibXml2 -ldl -lpthread -lm PkgConfig::deps ${CMAKE_DL_LIBS}
)

# Create a function for linking libraries, encapsulating repeated linking logic
function(config_link_libraries target_name)
    # Link libraries, passing all additional parameters as libraries
    target_link_libraries(${target_name}
        ${ARGN}
        ${CONFIG_COMMON_LIBS}
    )
endfunction()

# D-Bus interface generation
find_program(GDBUSCODEGEN NAMES gdbus-codegen)
if (NOT GDBUSCODEGEN)
	message(SEND_ERROR "Could not find gdbus-codegen")
endif(NOT GDBUSCODEGEN)

add_custom_command(
	OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.c ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h
	COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/generated
	COMMAND ${GDBUSCODEGEN} 
		--generate-c-code=${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated 
		--c-namespace=RollingGdbus 
		--interface-prefix com.rolling. 
		${CMAKE_SOURCE_DIR}/application/dbus/introspection/com.rolling.helper.xml
	DEPENDS ${CMAKE_SOURCE_DIR}/application/dbus/introspection/com.rolling.helper.xml
	COMMENT "Generating D-Bus interface code for config service"
)

##################################
# Configure library file paths
set(include_paths
    ${PROJECT_BINARY_DIR}/
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_SOURCE_DIR}/application/include/common
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${PROJECT_BINARY_DIR}/../3rd/iniparser
    ${CMAKE_CURRENT_BINARY_DIR}/generated
)
include_directories(${include_paths})

# Source file definition
aux_source_directory(./src CONFIG_SOURCES)
# Remove rolling_config_main.c from source file list, it will be used separately when generating executable
list(REMOVE_ITEM CONFIG_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/src/rolling_config_main.c)
list(APPEND CONFIG_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.c)

# Configuration file processing
set(build_project ${PROJECT_BUILD}_${OEM_BUILD})
set(file_path "")

file(GLOB SUBDIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/config_set/*")
foreach(SUBDIRS ${SUBDIRECTORIES})
    if(IS_DIRECTORY ${SUBDIRS})
        get_filename_component(SUBDIR_M ${SUBDIRS} NAME)
        if (${build_project} STREQUAL ${SUBDIR_M})
            set(file_path ${SUBDIR_M})
            message(STATUS "[ini useing]config service find config path ${file_path}")
            break()
        endif()
    endif()
endforeach()

if(file_path STREQUAL "")
    set(file_path "generic")
    message(STATUS "[ini useing]config service not find config path use default path ${file_path}")
endif()

# Copy configuration file to build directory
execute_process(COMMAND mkdir -p ${PROJECT_BINARY_DIR})
execute_process(COMMAND cp ${CMAKE_CURRENT_SOURCE_DIR}/config_set/${file_path}/rwwwanConfig.ini ${PROJECT_BINARY_DIR})

# Initialize build_by_lib variable
set(build_by_lib 0)

# Check BUILD_BY_LIB parameter, convert it to build_by_lib variable
if(DEFINED BUILD_BY_LIB)
    set(build_by_lib ${BUILD_BY_LIB})
    message(STATUS "BUILD_BY_LIB parameter: ${BUILD_BY_LIB}")
endif()

# When build_by_lib is 1, set BUILD_LIB to no
if(build_by_lib)
    set(BUILD_LIB "no")
    message(STATUS "Build by lib mode enabled, setting BUILD_LIB=no")
endif()

# Determine output target based on build mode
# Prioritize checking build_by_lib mode, generate executable from prebuilt static library
if(build_by_lib)
    # When build_by_lib=1, skip source code compilation, build only from library files
    message(STATUS "Build by lib mode: using prebuilt static library")
    # Static library path points to common library files in binary_deb/common_lib directory
    set(STATIC_LIB_PATH "${CMAKE_SOURCE_DIR}/binary_deb/common_lib/librolling_config_service_${CONFIG_VERSION_STRING}.a")
    message(STATUS "Using static library: ${STATIC_LIB_PATH}")

    # Build generic executable, use actual rolling_config_main.c file
    add_executable(rolling_config ${CMAKE_CURRENT_SOURCE_DIR}/src/rolling_config_main.c)
    # Link static library
    config_link_libraries(rolling_config ${STATIC_LIB_PATH})
    message(STATUS "Building generic executable using library: rolling_config")
elseif (BUILD_LIB)
    # Build static library mode
    message(STATUS "Building config service as static library")
    add_library(rolling_config_service_${CONFIG_VERSION_STRING} STATIC ${CONFIG_SOURCES})
    config_link_libraries(rolling_config_service_${CONFIG_VERSION_STRING})

else()
    # Build executable mode
    message(STATUS "Building config service as executable")
    # Build generic executable, add rolling_config_main.c
    add_executable(rolling_config ${CONFIG_SOURCES} ${CMAKE_CURRENT_SOURCE_DIR}/src/rolling_config_main.c)
    config_link_libraries(rolling_config)
    message(STATUS "Building generic executable: rolling_config")
endif()

# Static library build and copy functionality - using exactly the same directory structure and copy paths as helper_service and flash_service
if (build_by_code AND BUILD_LIB)
    # Set library output path exactly the same as helper_service and flash_service
    set(lib_path ${PROJECT_BINARY_DIR}/../../common_lib)

    # Define static library name
    set(STATIC_LIB_NAME "librolling_config_service_${CONFIG_VERSION_STRING}.a")

    # Create a unified config_build_lib target to avoid duplicate code
    add_custom_target(
        config_build_lib
        # Create output directory (using -p parameter to ensure directory exists without error)
        COMMAND mkdir -p ${lib_path}
        # Ensure static library is built
        COMMAND ${CMAKE_COMMAND} --build ${CMAKE_CURRENT_BINARY_DIR} --target rolling_config_service_${CONFIG_VERSION_STRING}
        # Check if D-Bus header file exists, if not, prompt error
        COMMAND test -f ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h || (echo "D-Bus header file not found!" && exit 1)
        # Copy static library built by config service
        COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/${STATIC_LIB_NAME} ${lib_path}
        # Copy all header files to common library directory
        COMMAND cp -f ${CMAKE_CURRENT_SOURCE_DIR}/include/*.h ${lib_path}
        # Copy D-Bus generated header files to common library directory
        COMMAND cp -f ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
        DEPENDS rolling_config_service_${CONFIG_VERSION_STRING}
        COMMENT "Config service build lib successfully"
    )
endif()
