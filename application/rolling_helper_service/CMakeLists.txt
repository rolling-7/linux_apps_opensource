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
set(HELPER_PATCH_VERSION 23)
set(HELPER_VERSION_STRING ${HELPER_MAJOR_VERSION}.${HELPER_MINOR_VERSION}.${HELPER_PATCH_VERSION})
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/version.h.in"
                "./version.h")

file(GLOB HELPER_DIR "./*")
foreach(SUBDIRS ${HELPER_DIR})
    get_filename_component(SUBDIR_M ${SUBDIRS} NAME)
    if (${SUBDIR_M} STREQUAL "common")
        add_subdirectory(./common)
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
pkg_check_modules(deps REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0 gio-unix-2.0  mbim-glib)
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
set(build_by_code 0)
set(build_by_lib 1)

add_definitions(${HELPER_PREPROCESSOR_DEF})
file(GLOB SUBDIRECTORIES "./*")
foreach(SUBDIRS ${SUBDIRECTORIES})
    if(${BUILD_LIB} STREQUAL "yes")
        set(build_by_code 1)
        message(STATTUS "build lib not build exe")
        break()
    endif()
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
                        # string(REPLACE ".a" "" exe_prefix "${suffix}")
                        message("executable lib:${exe_prefix}")
                        add_executable(${exe_prefix}_rolling_helper ${helper_source_files})
                        target_link_libraries(${exe_prefix}_rolling_helper ${file} LibXml2::LibXml2 udev PkgConfig::deps ${CMAKE_CURRENT_SOURCE_DIR}/common_lib/libcode.a
                                stdc++ stdc++fs)
                    endif()
                else()
                    set(PROJECT_BUILD rw101)
                    set(OEM_BUILD lenovo)
                    foreach(project ${PROJECT_BUILD})
                        foreach(oem ${OEM_BUILD})
                            set(pattern ".*${project}_${oem}.*")
                            string(REGEX MATCH "${pattern}" is_matched "${lib_name}")
                            if(is_matched)
                                string(LENGTH "${lib_name}" string_length)
                                set(start_index 3)
                                math(EXPR end_index "${string_length} - 11") 
                                string(SUBSTRING "${lib_name}" ${start_index} ${end_index} exe_prefix)
                                # string(REPLACE ".a" "" exe_prefix "${suffix}")
                                message("executable lib:${exe_prefix}")
                                add_executable(${exe_prefix}_rolling_helper ${helper_source_files})
                                target_link_libraries(${exe_prefix}_rolling_helper ${file} LibXml2::LibXml2 udev PkgConfig::deps ${CMAKE_CURRENT_SOURCE_DIR}/common_lib/libcode.a
                                stdc++ stdc++fs)
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
                            add_executable(${SUBDIR_M}_${SUBDIR_N}_${SUBDIR_NAME}_rolling_helper ${helper_source_files})
                            target_link_libraries(${SUBDIR_M}_${SUBDIR_N}_${SUBDIR_NAME}_rolling_helper LibXml2::LibXml2 PkgConfig::deps code 
                                                common_${SUBDIR_M}_${SUBDIR_N}_${SUBDIR_NAME})
                        endif()
                    endforeach()
                endif()
            endforeach()
        endif()
    endif()
endforeach()

if (build_by_code AND (${BUILD_LIB} STREQUAL "yes"))
    set(lib_path ${PROJECT_BINARY_DIR}/../../common_lib)
    if ((${PROJECT_BUILD} STREQUAL "rw101"))
        add_custom_target(
            helper_build_lib
            COMMAND mkdir ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/libqualcomm*.a ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/code/lib*.a ${lib_path}
            COMMAND cp  -raf ${CMAKE_CURRENT_SOURCE_DIR}/common/rolling_helper_common.h ${lib_path}
            COMMAND cp  -raf ${CMAKE_CURRENT_SOURCE_DIR}/common/rolling_helper_basic_func.h ${lib_path}
            COMMAND cp  -raf ${CMAKE_CURRENT_SOURCE_DIR}/common/common_base_func.h ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "helper service build lib successfully"
        )
    else()
        add_custom_target(
            helper_build_lib
            COMMAND mkdir ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/libqualcomm*.a ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/libmtk*.a ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/code/lib*.a ${lib_path}
            COMMAND cp  -raf ${CMAKE_CURRENT_SOURCE_DIR}/common/rolling_helper_common.h ${lib_path}
            COMMAND cp  -raf ${CMAKE_CURRENT_SOURCE_DIR}/common/rolling_helper_basic_func.h ${lib_path}
            COMMAND cp  -raf ${CMAKE_CURRENT_SOURCE_DIR}/common/common_base_func.h ${lib_path}
            COMMAND cp  -raf ${PROJECT_BINARY_DIR}/common/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "helper service build lib successfully"
        )
    endif()
endif()
