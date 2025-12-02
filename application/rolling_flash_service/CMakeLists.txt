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
# 版本配置
set(FLASH_MAJOR_VERSION 2)
set(FLASH_MINOR_VERSION 0)
set(FLASH_PATCH_VERSION 12)
set(FLASH_VERSION_STRING ${FLASH_MAJOR_VERSION}.${FLASH_MINOR_VERSION}.${FLASH_PATCH_VERSION})
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/version.h.in"
				"./version.h")

# 编译选项设置
set(CMAKE_C_COMPILER gcc)
set(FLASH_PREPROCESSOR_DEF "-fstack-protector-strong -O2 -Wformat -Wformat-security  -fPIC -std=gnu99")
add_compile_options(-pthread) 

# 检查BUILD_BY_LIB参数
set(build_by_lib 0)
if(DEFINED BUILD_BY_LIB)
    set(build_by_lib ${BUILD_BY_LIB})
    message(STATUS "BUILD_BY_LIB parameter: ${BUILD_BY_LIB}")
endif()

# 当build_by_lib为1时，设置BUILD_LIB为no
if(build_by_lib)
    set(BUILD_LIB "no")
    message(STATUS "build_by_lib=1, setting BUILD_LIB=no")
endif()

# 当BUILD_LIB为yes时，自动设置build_by_code为1，与helper_service保持一致
if(${BUILD_LIB} STREQUAL "yes")
    set(build_by_code 1)
    message(STATUS "Build lib mode enabled, setting build_by_code=1")
else()
    set(build_by_code 0)
	message(STATUS "Build exe mode enabled, setting build_by_code=0")
endif()

# 依赖查找
find_package(LibXml2 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0 gio-unix-2.0)

# 添加预处理定义
add_definitions(${FLASH_PREPROCESSOR_DEF})

# D-Bus 接口生成
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
# 配置库文件路径
set(include_paths
    ${PROJECT_BINARY_DIR}/
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_SOURCE_DIR}/application/include/common
	${CMAKE_SOURCE_DIR}/application/3rd/safestringlib/include
    ### ${PROJECT_BINARY_DIR}/../3rd/safestringlib/include
	${CMAKE_CURRENT_SOURCE_DIR}/build
	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_CURRENT_BINARY_DIR}/generated
)
include_directories(${include_paths})

# 源文件定义
set(source_files
    rolling_flash_main.c 
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

# 复制配置文件到构建目录
execute_process(COMMAND mkdir -p ${PROJECT_BINARY_DIR})
execute_process(COMMAND cp ${CMAKE_CURRENT_SOURCE_DIR}/flash_set/${file_path}/FwUpdate.ini ${PROJECT_BINARY_DIR})

# D-Bus 接口生成 - 无论哪种构建模式都需要生成
find_program(GDBUSCODEGEN NAMES gdbus-codegen)
if (NOT GDBUSCODEGEN)
	message(SEND_ERROR "Could not find gdbus-codegen")
endif(NOT GDBUSCODEGEN)

add_custom_command(
	OUTPUT generated/rolling-helper-gdbus-generated.c generated/rolling-helper-gdbus-generated.h
	COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/generated
	COMMAND ${GDBUSCODEGEN}  --generate-c-code=${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated --c-namespace=RollingGdbus --interface-prefix com.rolling. ${CMAKE_SOURCE_DIR}/application/dbus/introspection/com.rolling.helper.xml
	)

# 创建一个自定义目标来确保D-Bus接口文件被生成
add_custom_target(flash_dbus_generated ALL DEPENDS generated/rolling-helper-gdbus-generated.c generated/rolling-helper-gdbus-generated.h)

# 根据构建模式决定输出目标
# 优先检查build_by_lib模式，从预构建静态库生成可执行文件
if(build_by_lib)
	# 当build_by_lib=1时，跳过源码编译，只从库文件构建
	message(STATUS "STATTUSbuild lib not build exe")
	# 静态库路径指向binary_deb/common_lib目录下的通用库文件
	set(STATIC_LIB_PATH "${CMAKE_SOURCE_DIR}/binary_deb/common_lib/librolling_flash_service_${FLASH_VERSION_STRING}.a")
	message(STATUS "Using static library: ${STATIC_LIB_PATH}")
	
	# 创建一个简单的空源文件，用于满足CMake的add_executable要求
	file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/empty.c "")
	
	# 构建通用可执行文件（无论是否指定了特定项目和OEM，都生成相同的可执行文件名）
	add_executable(rolling_flash ${CMAKE_CURRENT_BINARY_DIR}/empty.c)
	# 链接静态库
	target_link_libraries(rolling_flash
		${STATIC_LIB_PATH}
		${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
		PkgConfig::deps
		LibXml2::LibXml2
	)
	message(STATUS "Building generic executable using library: rolling_flash")
# 然后检查BUILD_LIB模式，构建静态库，但只有当build_by_lib不为1时才执行
elseif (${BUILD_LIB} STREQUAL "yes" AND NOT build_by_lib)
	# 构建静态库模式
	message(STATUS "Building flash service as static library")
	add_library(rolling_flash_service_${FLASH_VERSION_STRING} STATIC ${source_files})
	target_link_libraries(rolling_flash_service_${FLASH_VERSION_STRING}
		${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
		PkgConfig::deps
		LibXml2::LibXml2
	)
	
	# 安装静态库
	install(TARGETS rolling_flash_service_${FLASH_VERSION_STRING} DESTINATION lib)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h DESTINATION include)
	
	# 同时构建可执行文件
	message(STATUS "Building flash service executable in BUILD_LIB mode")
	add_executable(rolling_flash ${source_files})
	target_link_libraries(rolling_flash
		${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
		PkgConfig::deps
		LibXml2::LibXml2
	)
# 最后检查常规可执行文件构建模式
elseif(NOT build_by_lib)
	# 构建可执行文件模式
	message(STATUS "Building flash service as executable")
	
	# 检查是否指定了特定项目和OEM
	if ((NOT ${PROJECT_BUILD} STREQUAL OFF) AND (NOT ${OEM_BUILD} STREQUAL OFF))
		# 构建特定项目和OEM的可执行文件
		add_executable(${PROJECT_BUILD}_${OEM_BUILD}_rolling_flash ${source_files})
		target_link_libraries(${PROJECT_BUILD}_${OEM_BUILD}_rolling_flash
			${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
			PkgConfig::deps
			LibXml2::LibXml2
		)
		message(STATUS "Building specific executable: ${PROJECT_BUILD}_${OEM_BUILD}_rolling_flash")
	else()
		# 构建通用可执行文件
		add_executable(rolling_flash ${source_files})
		target_link_libraries(rolling_flash
			${PROJECT_BINARY_DIR}/../3rd/safestringlib/libsafestring_static.a
			PkgConfig::deps
			LibXml2::LibXml2
		)
		message(STATUS "Building generic executable: rolling_flash")
	endif()
endif()

# 静态库构建与复制功能 - 与helper_service使用完全相同的目录结构和复制路径
if (build_by_code AND (${BUILD_LIB} STREQUAL "yes"))
    # 设置与helper_service完全相同的库输出路径
    set(lib_path ${PROJECT_BINARY_DIR}/../../common_lib)
    
    # 根据不同项目类型创建相应的build_lib目标，使用与helper_service完全相同的目录结构
    if ((${PROJECT_BUILD} STREQUAL "rw101") OR (${PROJECT_BUILD} STREQUAL "rw135")) 
		add_custom_target(
			flash_build_lib
            # 创建输出目录（使用-p参数确保目录存在不会报错）
            COMMAND mkdir -p ${lib_path}
            # 复制flash服务构建的静态库
            COMMAND cp -raf ${PROJECT_BINARY_DIR}/librolling_flash_service_${FLASH_VERSION_STRING}.a ${lib_path}
            # 复制flash服务相关的头文件
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_parse_xml.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_prepare.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_signal.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_update.h ${lib_path}
            # 复制D-Bus接口头文件
            COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "Flash service build lib successfully"
		)
    elseif(${PROJECT_BUILD} STREQUAL "rw350")
		add_custom_target(
			flash_build_lib
            # 创建输出目录（使用-p参数确保目录存在不会报错）
            COMMAND mkdir -p ${lib_path}
            # 复制flash服务构建的静态库
            COMMAND cp -raf ${PROJECT_BINARY_DIR}/librolling_flash_service_${FLASH_VERSION_STRING}.a ${lib_path}
            # 复制flash服务相关的头文件
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_parse_xml.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_prepare.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_signal.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_update.h ${lib_path}
            # 复制D-Bus接口头文件
            COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "Flash service build lib successfully"
		)
    else()
		add_custom_target(
			flash_build_lib
            # 创建输出目录（使用-p参数确保目录存在不会报错）
            COMMAND mkdir -p ${lib_path}
            # 复制flash服务构建的静态库
            COMMAND cp -raf ${PROJECT_BINARY_DIR}/librolling_flash_service_${FLASH_VERSION_STRING}.a ${lib_path}
            # 复制flash服务相关的头文件
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_common.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_main.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_parse_xml.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_prepare.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_signal.h ${lib_path}
            COMMAND cp -raf ${CMAKE_CURRENT_SOURCE_DIR}/rolling_flash_update.h ${lib_path}
            # 复制D-Bus接口头文件
            COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
            COMMENT "Flash service build lib successfully"
		)
    endif()
endif()