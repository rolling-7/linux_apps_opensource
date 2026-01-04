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
project(rolling_helper_service)

set(HELPER_MAJOR_VERSION 2)
set(HELPER_MINOR_VERSION 0)
set(HELPER_PATCH_VERSION 24)
set(HELPER_VERSION_STRING ${HELPER_MAJOR_VERSION}.${HELPER_MINOR_VERSION}.${HELPER_PATCH_VERSION})
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/version.h.in"
                "./version.h")

file(GLOB HELPER_DIR "./*")
foreach(SUBDIRS ${HELPER_DIR})
    get_filename_component(SUBDIR_M ${SUBDIRS} NAME)
    if (${SUBDIR_M} STREQUAL "common")
        # Only add common subdirectory when build_by_lib is 0
        if(NOT build_by_lib)
            add_subdirectory(./common)
        endif()
        break()
    elseif(${SUBDIR_M} STREQUAL "common_lib")
        include_directories(${CMAKE_CURRENT_SOURCE_DIR}/common_lib)
        break()
    endif()
endforeach()

set(CMAKE_C_COMPILER gcc)
set(HELPER_PREPROCESSOR_DEF "-fstack-protector-strong -O2 -Wformat -Wformat-security  -fPIC -std=gnu99")
find_package(PkgConfig REQUIRED)
find_package(LibXml2 REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0 gio-unix-2.0 mbim-glib mm-glib)
##################################

##################################
# Rolling linux helper service binary configuration
add_compile_options(-pthread)
set(path ${CMAKE_SOURCE_DIR}/application/include/common/ 
${PROJECT_BINARY_DIR}/ ${CMAKE_CURRENT_SOURCE_DIR}/common 
${PROJECT_BINARY_DIR}/common)
include_directories(${path})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../include
                    /usr/include/libmbim-glib
                    /usr/local/include/libmbim-glib
                    ${CMAKE_CURRENT_SOURCE_DIR})

set(helper_source_files rolling_helper_main.c)

set(build_by_code 1)

# Check BUILD_BY_LIB parameter, convert it to build_by_lib variable
if(DEFINED BUILD_BY_LIB)
    set(build_by_lib ${BUILD_BY_LIB})
    message(STATUS "BUILD_BY_LIB parameter: ${BUILD_BY_LIB}")
endif()

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

add_definitions(${HELPER_PREPROCESSOR_DEF})

# Define common link library variables
set(HELPER_COMMON_LIBS
    PkgConfig::deps
    LibXml2::LibXml2
    udev
    stdc++
    stdc++fs
)

# Define common link library variables (with safestring)
set(HELPER_COMMON_LIBS_WITH_SAFESTRING
    ${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
    ${HELPER_COMMON_LIBS}
)

# Create a function for linking libraries, encapsulating repeated linking logic
function(helper_link_libraries target_name)
    # Link libraries, passing all additional parameters as libraries
    target_link_libraries(${target_name}
        ${ARGN}
        ${HELPER_COMMON_LIBS_WITH_SAFESTRING}
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

# Create a custom target to ensure D-Bus interface files are generated
add_custom_target(helper_dbus_generated ALL DEPENDS generated/rolling-helper-gdbus-generated.c generated/rolling-helper-gdbus-generated.h)

# Add generated directory to include path
include_directories(${CMAKE_CURRENT_BINARY_DIR}/generated)

# Determine output target based on build mode
# Prioritize checking build_by_lib mode, generate executable from prebuilt static library
if(build_by_lib)
    # When build_by_lib=1, skip source code compilation, build only from library files
    message(STATUS "STATTUSbuild lib not build exe")

    # Static library path points to common library files in binary_deb/common_lib directory
    set(STATIC_LIB_PATH "${CMAKE_SOURCE_DIR}/binary_deb/common_lib/libqualcomm_${PROJECT_BUILD}_${OEM_BUILD}_${HELPER_VERSION_STRING}.a")
    message(STATUS "Using static library: ${STATIC_LIB_PATH}")

    # Build generic executable, use actual rolling_helper_main.c file
    add_executable(rolling_helper ${CMAKE_CURRENT_SOURCE_DIR}/rolling_helper_main.c)
    # Link static library
    helper_link_libraries(rolling_helper "${STATIC_LIB_PATH}" "${CMAKE_SOURCE_DIR}/binary_deb/common_lib/libcode.a")
    message(STATUS "Building generic executable using library: rolling_helper")
# Then check BUILD_LIB mode, build static library, but only if build_by_lib is not 1
elseif (BUILD_LIB AND NOT build_by_lib)
    # Build static library mode
    message(STATUS "Building helper service as static library")

    # Collect all source files (including source files under common directory and generated D-Bus files)
    file(GLOB COMMON_SOURCE_FILES "${CMAKE_CURRENT_SOURCE_DIR}/common/*.c")
    # Do not include rolling_helper_main.c when building static library, it will be used separately when generating executable
    set(ALL_SOURCE_FILES 
        ${COMMON_SOURCE_FILES}
        ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.c
    )

    add_library(rolling_helper_service_${HELPER_VERSION_STRING} STATIC ${ALL_SOURCE_FILES})
    # Ensure static library build depends on D-Bus generation target
    add_dependencies(rolling_helper_service_${HELPER_VERSION_STRING} helper_dbus_generated)
    helper_link_libraries(rolling_helper_service_${HELPER_VERSION_STRING})

# Finally check regular executable build mode
elseif(NOT build_by_lib AND NOT BUILD_LIB)
    # Build executable mode
    message(STATUS "Building helper service as executable")

    # Regular build mode, traverse directory structure
    file(GLOB SUBDIRECTORIES "./*")
    foreach(SUBDIRS ${SUBDIRECTORIES})
        if(IS_DIRECTORY ${SUBDIRS})
            get_filename_component(SUBDIR_M ${SUBDIRS} NAME)
            if (${SUBDIR_M} STREQUAL "common")
                set(build_by_code 1)
                message(STATUS "Skipping ${SUBDIR_M}")
                continue()
            endif()
            if ((${SUBDIR_M} STREQUAL "common_lib") AND (NOT build_by_code))
                set(build_by_lib 1)
                file(GLOB file_names "${SUBDIR_M}/*.a")
                foreach(file ${file_names})
                    get_filename_component(lib_name ${file} NAME)
                    if ((NOT ${PROJECT_BUILD} STREQUAL OFF ) AND (NOT ${OEM_BUILD} STREQUAL OFF))
                        set(pattern ".*${PROJECT_BUILD}_${OEM_BUILD}.*")
                        string(REGEX MATCH "${pattern}" is_matched "${lib_name}")
                        if(is_matched)
                            string(LENGTH "${lib_name}" string_length)
                            set(start_index 3)
                            math(EXPR end_index "${string_length} - 11") 
                            string(SUBSTRING "${lib_name}" ${start_index} ${end_index} exe_prefix)
                            message("executable lib:${exe_prefix}")
                            add_executable(rolling_helper ${helper_source_files})
                            helper_link_libraries(rolling_helper "${file}" "${CMAKE_CURRENT_SOURCE_DIR}/common_lib/libcode.a")
                        endif()
                    else()
                        set(PROJECT_BUILD rw101 rw135 rw350)
                        set(OEM_BUILD dell lenovo hp)
                        foreach(project ${PROJECT_BUILD})
                            foreach(oem ${OEM_BUILD})
                                set(pattern ".*${project}_${oem}.*")
                                string(REGEX MATCH "${pattern}" is_matched "${lib_name}")
                                if(is_matched)
                                    string(LENGTH "${lib_name}" string_length)
                                    set(start_index 3)
                                    math(EXPR end_index "${string_length} - 11") 
                                    string(SUBSTRING "${lib_name}" ${start_index} ${end_index} exe_prefix)
                                    message("executable lib:${exe_prefix}")
                                    add_executable(${exe_prefix}_rolling_helper ${helper_source_files})
                                    helper_link_libraries(${exe_prefix}_rolling_helper "${file}" "${CMAKE_CURRENT_SOURCE_DIR}/common_lib/libcode.a")
                                endif()
                            endforeach()
                        endforeach()
                        set(PROJECT_BUILD )
                        set(OEM_BUILD )
                    endif()
                endforeach()
                break()
            else()
                file(GLOB SUBDIR "${SUBDIRS}/*")
                foreach(SUBDIR_X ${SUBDIR})
                    if(IS_DIRECTORY ${SUBDIR_X})
                        get_filename_component(SUBDIR_N ${SUBDIR_X} NAME)
                        file(GLOB SUBDIR_R "${SUBDIR_X}/*")
                        foreach(SUBDIR_INFO ${SUBDIR_R})
                            if(IS_DIRECTORY ${SUBDIR_INFO})
                                get_filename_component(SUBDIR_NAME ${SUBDIR_INFO} NAME)
                                if ((NOT ${PROJECT_BUILD} STREQUAL ${SUBDIR_N}) OR (NOT ${OEM_BUILD} STREQUAL ${SUBDIR_NAME}))
                                    if ((NOT ${PROJECT_BUILD} STREQUAL OFF ) AND (NOT ${OEM_BUILD} STREQUAL OFF))
                                        message(STATUS "EXEC Skipping ${SUBDIR_N}_${SUBDIR_NAME}")
                                        continue()
                                    endif()
                                endif()
                                message("executable lib: ${SUBDIR_M}_proj_${SUBDIR_N}_${SUBDIR_NAME}")
                                add_executable(rolling_helper ${helper_source_files})
                                # Note: Do not use helper_link_libraries function here, because it depends on common_${SUBDIR_M}_${SUBDIR_N}_${SUBDIR_NAME},
                                # and this target is defined in common/CMakeLists.txt, not in the current function's scope
                                target_link_libraries(rolling_helper LibXml2::LibXml2 PkgConfig::deps code 
                                                    common_${SUBDIR_M}_${SUBDIR_N}_${SUBDIR_NAME})
                            endif()
                        endforeach()
                    endif()
                endforeach()
            endif()
        endif()
    endforeach()
endif()
