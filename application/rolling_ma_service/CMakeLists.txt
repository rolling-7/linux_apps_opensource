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

project(rolling_ma_service)

find_package(PkgConfig REQUIRED)
find_package(LibXml2 REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0 gio-unix-2.0)

find_program(GDBUSCODEGEN NAMES gdbus-codegen)
if (NOT GDBUSCODEGEN)
	message(SEND_ERROR "Could not find gdbus-codegen")
endif(NOT GDBUSCODEGEN)

add_custom_command(OUTPUT generated/rolling-helper-gdbus-generated.c
		COMMAND ${GDBUSCODEGEN}  --generate-c-code=rolling-helper-gdbus-generated --c-namespace=RollingGdbus --interface-prefix com.rolling. ${CMAKE_SOURCE_DIR}/application/dbus/introspection/com.rolling.helper.xml
		COMMAND mkdir -p generated/
		COMMAND mv rolling-helper-gdbus-generated.c generated/
)

set(MA_MAJOR_VERSION 2)
set(MA_MINOR_VERSION 0)
set(MA_PATCH_VERSION 0)

set(MA_VERSION_STRING ${MA_MAJOR_VERSION}.${MA_MINOR_VERSION}.${MA_PATCH_VERSION})

set(MA_PREPROCESSOR_DEF "-fstack-protector-strong -O2 -Wformat -Wformat-security  -fPIC -std=gnu99")
add_definitions(${MA_PREPROCESSOR_DEF})

##################################
# Rolling linux ma service binary configuration
add_subdirectory(sha256)
add_subdirectory(bios)
add_compile_options(-pthread)
aux_source_directory(. DIR_SRCS)

include_directories(${PROJECT_BINARY_DIR}/)

include_directories(/usr/include/dbus-1.0
		/usr/lib/x86_64-linux-gnu/dbus-1.0/includels
		/usr/include/gio-unix-2.0
		/usr/include/libmount
		/usr/include/blkid
		/usr/include/glib-2.0
		/usr/lib/x86_64-linux-gnu/glib-2.0/include
		../libs/libxml2-v2.11.5/
		${CMAKE_SOURCE_DIR}/application/include/common/
		${CMAKE_SOURCE_DIR}/build/application/rolling_ma_service/
		.)
set(source_files rolling_ma_main.c generated/rolling-helper-gdbus-generated.c ${DIR_SRCS})
add_executable(rolling_ma ${source_files})
target_link_libraries(rolling_ma PkgConfig::deps
		LibXml2::LibXml2 dbus-1 udev gio-2.0 gobject-2.0 glib-2.0  random varient )

# Set binary_deb/common_lib output path
set(lib_output_path ${CMAKE_SOURCE_DIR}/binary_deb/common_lib)

# Output build information
message(STATUS "MA service configured with PROJECT_BUILD: ${PROJECT_BUILD}")
message(STATUS "MA service configured with OEM_BUILD: ${OEM_BUILD}")
message(STATUS "MA service lib output path: ${lib_output_path}")

# Create main target - only responsible for creating directories
add_custom_target(
    ma_build_lib
    # Create output directory
    COMMAND mkdir -p ${lib_output_path}
    COMMENT "MA service build lib and copy files according to OEM type"
)

# Add default build dependency to ensure copy operation is executed after building rolling_ma
add_dependencies(ma_build_lib rolling_ma)

# Execute different copy operations based on different OEM build types
# Lenovo OEM copy operation
if(OEM_BUILD STREQUAL "lenovo")
    add_custom_command(
        TARGET ma_build_lib POST_BUILD
        COMMAND echo "Copying libmodemauth.so.1.0 for Lenovo OEM"
        COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/libmodemauth.so.1.0 ${lib_output_path}
        VERBATIM
    )
# Dell OEM copy operation
elseif(OEM_BUILD STREQUAL "dell")
    add_custom_command(
        TARGET ma_build_lib POST_BUILD
        COMMAND echo "Copying rolling_ma for Dell OEM"
        COMMAND cp -raf ${PROJECT_BINARY_DIR}/rolling_ma ${lib_output_path}
        VERBATIM
    )
# Other OEM types
else()
    add_custom_command(
        TARGET ma_build_lib POST_BUILD
        COMMAND echo "No specific copy action for OEM: ${OEM_BUILD}"
        VERBATIM
    )
endif()
