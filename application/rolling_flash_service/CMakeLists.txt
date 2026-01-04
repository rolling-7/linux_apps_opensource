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
project(rolling_flash_service)
# Version configuration
set(FLASH_MAJOR_VERSION 2)
set(FLASH_MINOR_VERSION 0)
set(FLASH_PATCH_VERSION 13)
set(FLASH_VERSION_STRING ${FLASH_MAJOR_VERSION}.${FLASH_MINOR_VERSION}.${FLASH_PATCH_VERSION})
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/version.h.in"
			"./version.h")

# Compilation options setting
set(CMAKE_C_COMPILER gcc)
set(FLASH_PREPROCESSOR_DEF "-fstack-protector-strong -O2 -Wformat -Wformat-security  -fPIC -std=gnu99")
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
pkg_check_modules(FWUPD REQUIRED fwupd)

# Add preprocessor definitions
add_definitions(${FLASH_PREPROCESSOR_DEF})

# Define common link library variables
set(FLASH_COMMON_LIBS
    ${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
    PkgConfig::deps
    LibXml2::LibXml2
)

# Create a function for linking libraries, encapsulating repeated linking logic
function(flash_link_libraries target_name)
    # Link libraries, passing all additional parameters as libraries
    target_link_libraries(${target_name}
        ${ARGN}
        ${FLASH_COMMON_LIBS}
		${FWUPD_LIBRARIES}
    )
endfunction()

# D-Bus interface generation
find_program(GDBUSCODEGEN NAMES gdbus-codegen)
if (NOT GDBUSCODEGEN)
	message(SEND_ERROR "Could not find gdbus-codegen")
endif(NOT GDBUSCODEGEN)

add_custom_command(
	OUTPUT generated/rolling-helper-gdbus-generated.c generated/rolling-helper-gdbus-generated.h
	COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/generated
	COMMAND ${GDBUSCODEGEN}  --generate-c-code=${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated --c-namespace=RollingGdbus --interface-prefix com.rolling. ${CMAKE_SOURCE_DIR}/application/dbus/introspection/com.rolling.helper.xml
	)

##################################
# Configure library file paths
set(include_paths
    ${PROJECT_BINARY_DIR}/
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_SOURCE_DIR}/application/include/common
	${CMAKE_SOURCE_DIR}/application/3rd/safestringlib/include
    ### ${PROJECT_BINARY_DIR}/../3rd/safestringlib/include
	${CMAKE_CURRENT_SOURCE_DIR}/build
	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_CURRENT_BINARY_DIR}/generated
	${FWUPD_INCLUDE_DIRS}
)
include_directories(${include_paths})

# Source file definition
set(source_files
	rolling_flash_download.c
	rolling_flash_parse_xml.c
	rolling_flash_common.c
	rolling_flash_prepare.c
	rolling_flash_signal.c
	rolling_flash_update.c
	rolling_flash_recovery.c
	${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.c
)

set(build_project ${PROJECT_BUILD}_${OEM_BUILD})
set(file_path "")

file(GLOB SUBDIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/flash_set/*")
foreach(SUBDIRS ${SUBDIRECTORIES})
    if(IS_DIRECTORY ${SUBDIRS})
        get_filename_component(SUBDIR_M ${SUBDIRS} NAME)
        if (${build_project} STREQUAL ${SUBDIR_M})
            set(file_path ${SUBDIR_M})
            message(STATUS "[ini useing]flash service find config path ${file_path}")
            break()
        endif()
    endif()
endforeach()

if(file_path STREQUAL "")
    set(file_path "generic")
    message(STATUS "[ini useing]flash service not find config path use default path ${file_path}")
endif()

# Copy configuration file to build directory
execute_process(COMMAND mkdir -p ${PROJECT_BINARY_DIR})
execute_process(COMMAND cp ${CMAKE_CURRENT_SOURCE_DIR}/flash_set/${file_path}/FwUpdate.ini ${PROJECT_BINARY_DIR})

# D-Bus interface generation - Required for all build modes
find_program(GDBUSCODEGEN NAMES gdbus-codegen)
if (NOT GDBUSCODEGEN)
	message(SEND_ERROR "Could not find gdbus-codegen")
endif(NOT GDBUSCODEGEN)

# Create a custom target to ensure D-Bus interface files are generated
add_custom_target(flash_dbus_generated ALL DEPENDS generated/rolling-helper-gdbus-generated.c generated/rolling-helper-gdbus-generated.h)

# Determine output target based on build mode
# Prioritize checking build_by_lib mode, generate executable from prebuilt static library
if(build_by_lib)
    # When build_by_lib=1, skip source code compilation, build only from library files
    message(STATUS "STATTUSbuild lib not build exe")
    # Static library path points to common library files in binary_deb/common_lib directory
    set(STATIC_LIB_PATH "${CMAKE_SOURCE_DIR}/binary_deb/common_lib/librolling_flash_service_${FLASH_VERSION_STRING}.a")
    message(STATUS "Using static library: ${STATIC_LIB_PATH}")

    # Build generic executable, use actual rolling_flash_main.c file
    add_executable(rolling_flash ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.c)
    # Link static library
    flash_link_libraries(rolling_flash ${STATIC_LIB_PATH})
    message(STATUS "Building generic executable using library: rolling_flash")
# Then check BUILD_LIB mode, build static library, but only if build_by_lib is not 1
elseif (BUILD_LIB AND NOT build_by_lib)
    # Build static library mode
    message(STATUS "Building flash service as static library")
    add_library(rolling_flash_service_${FLASH_VERSION_STRING} STATIC ${source_files})
    flash_link_libraries(rolling_flash_service_${FLASH_VERSION_STRING})

# Finally check regular executable build mode
elseif(NOT build_by_lib)
    # Build executable mode
    message(STATUS "Building flash service as executable")
    # Build generic executable, add rolling_flash_main.c
    add_executable(rolling_flash ${source_files} ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.c)
    flash_link_libraries(rolling_flash)
    message(STATUS "Building generic executable: rolling_flash")
endif()

# Static library build and copy functionality - using exactly the same directory structure and copy paths as helper_service
if (build_by_code AND BUILD_LIB)
    # Set library output path exactly the same as helper_service
    set(lib_path ${PROJECT_BINARY_DIR}/../../common_lib)

    # Create corresponding build_lib targets based on different project types, using exactly the same directory structure as helper_service
    if ((${PROJECT_BUILD} STREQUAL "rw101")) 
        add_custom_target(
            flash_build_lib
            # Create output directory (using -p parameter to ensure directory exists without error)
            COMMAND mkdir -p ${lib_path}
            # Copy static library built by flash service
            COMMAND cp -raf ${PROJECT_BINARY_DIR}/librolling_flash_service_${FLASH_VERSION_STRING}.a ${lib_path}
            # Copy flash service related header files
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_parse_xml.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_prepare.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_signal.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_update.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_download.h ${lib_path}
            # Copy D-Bus interface header files
            COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "Flash service build lib successfully"
        )
    elseif(${PROJECT_BUILD} STREQUAL "rw350")
        add_custom_target(
            flash_build_lib
            # Create output directory (using -p parameter to ensure directory exists without error)
            COMMAND mkdir -p ${lib_path}
            # Copy static library built by flash service
            COMMAND cp -raf ${PROJECT_BINARY_DIR}/librolling_flash_service_${FLASH_VERSION_STRING}.a ${lib_path}
            # Copy flash service related header files
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_parse_xml.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_prepare.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_signal.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_update.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_download.h ${lib_path}
            # Copy D-Bus interface header files
            COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "Flash service build lib successfully"
        )
    else()
        add_custom_target(
            flash_build_lib
            # Create output directory (using -p parameter to ensure directory exists without error)
            COMMAND mkdir -p ${lib_path}
            # Copy static library built by flash service
            COMMAND cp -raf ${PROJECT_BINARY_DIR}/librolling_flash_service_${FLASH_VERSION_STRING}.a ${lib_path}
            # Copy flash service related header files
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_parse_xml.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_prepare.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_signal.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_update.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_download.h ${lib_path}
            # Copy D-Bus interface header files
            COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "Flash service build lib successfully"
        )
    endif()
endif()
