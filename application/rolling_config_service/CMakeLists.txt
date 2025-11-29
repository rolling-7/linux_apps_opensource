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

# 版本配置
set(CONFIG_MAJOR_VERSION 2)
set(CONFIG_MINOR_VERSION 0)
set(CONFIG_PATCH_VERSION 9)
set(CONFIG_VERSION_STRING ${CONFIG_MAJOR_VERSION}.${CONFIG_MINOR_VERSION}.${CONFIG_PATCH_VERSION})
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/version.h.in"
		"./version.h")

# 编译选项设置
set(CMAKE_C_COMPILER gcc)
set(CONFIG_PREPROCESSOR_DEF "-fstack-protector-strong -O2 -Wformat -Wformat-security  -fPIC -std=gnu99")
add_compile_options(-pthread)

# 检查是否构建静态库
set(build_by_code 0)

# 当BUILD_LIB为yes时，自动设置build_by_code为1，与helper_service和flash_service保持一致
if(${BUILD_LIB} STREQUAL "yes")
    set(build_by_code 1)
    message(STATUS "Build lib mode enabled, setting build_by_code=1")
endif()

# 依赖查找
find_package(LibXml2 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0 gio-unix-2.0)

# 添加预处理定义
add_definitions(${CONFIG_PREPROCESSOR_DEF})

# D-Bus 接口生成
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
# 配置库文件路径
set(include_paths
    ${PROJECT_BINARY_DIR}/
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_SOURCE_DIR}/application/include/common
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${PROJECT_BINARY_DIR}/../3rd/iniparser
    ${CMAKE_CURRENT_BINARY_DIR}/generated
)
include_directories(${include_paths})

# 源文件定义
aux_source_directory(./src CONFIG_SOURCES)
list(APPEND CONFIG_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.c)

# 配置文件处理
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

# 复制配置文件到构建目录
execute_process(COMMAND mkdir -p ${PROJECT_BINARY_DIR})
execute_process(COMMAND cp ${CMAKE_CURRENT_SOURCE_DIR}/config_set/${file_path}/rwwwanConfig.ini ${PROJECT_BINARY_DIR})

# 根据构建模式决定输出目标
if (${BUILD_LIB} STREQUAL "yes")
	# 构建静态库模式
	message(STATUS "Building config service as static library")
	add_library(rolling_config_service_${CONFIG_VERSION_STRING} STATIC ${CONFIG_SOURCES})
	target_link_libraries(rolling_config_service_${CONFIG_VERSION_STRING}
		${PROJECT_BINARY_DIR}/../3rd/iniparser/libiniparser.a
		LibXml2::LibXml2 -ldl -lpthread -lm PkgConfig::deps ${CMAKE_DL_LIBS}
	)
	
	# 安装静态库
	install(TARGETS rolling_config_service_${CONFIG_VERSION_STRING} DESTINATION lib)
	install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/ DESTINATION include)
else()
	# 构建可执行文件模式
	message(STATUS "Building config service as executable")
	
	# 检查是否指定了特定项目和OEM
	if ((NOT ${PROJECT_BUILD} STREQUAL OFF) AND (NOT ${OEM_BUILD} STREQUAL OFF))
		# 构建特定项目和OEM的可执行文件
		add_executable(${PROJECT_BUILD}_${OEM_BUILD}_rolling_config ${CONFIG_SOURCES})
		target_link_libraries(${PROJECT_BUILD}_${OEM_BUILD}_rolling_config
			${PROJECT_BINARY_DIR}/../3rd/iniparser/libiniparser.a
			LibXml2::LibXml2 -ldl -lpthread -lm PkgConfig::deps ${CMAKE_DL_LIBS}
		)
		message(STATUS "Building specific executable: ${PROJECT_BUILD}_${OEM_BUILD}_rolling_config")
	else()
		# 构建通用可执行文件
		add_executable(rolling_config ${CONFIG_SOURCES})
		target_link_libraries(rolling_config
			${PROJECT_BINARY_DIR}/../3rd/iniparser/libiniparser.a
			LibXml2::LibXml2 -ldl -lpthread -lm PkgConfig::deps ${CMAKE_DL_LIBS}
		)
		message(STATUS "Building generic executable: rolling_config")
	endif()
endif()

# 静态库构建与复制功能 - 与helper_service和flash_service使用完全相同的目录结构和复制路径
if (build_by_code AND (${BUILD_LIB} STREQUAL "yes"))
    # 设置与helper_service和flash_service完全相同的库输出路径
    set(lib_path ${PROJECT_BINARY_DIR}/../../common_lib)
    
    # 定义静态库名称
    set(STATIC_LIB_NAME "librolling_config_service_${CONFIG_VERSION_STRING}.a")
    
    # 创建一个统一的config_build_lib目标，避免重复代码
    add_custom_target(
        config_build_lib
        # 创建输出目录（使用-p参数确保目录存在不会报错）
        COMMAND mkdir -p ${lib_path}
        # 确保静态库已构建
        COMMAND ${CMAKE_COMMAND} --build ${CMAKE_CURRENT_BINARY_DIR} --target rolling_config_service_${CONFIG_VERSION_STRING}
        # 检查D-Bus头文件是否存在，如果不存在则提示错误
        COMMAND test -f ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h || (echo "D-Bus header file not found!" && exit 1)
        # 复制config服务构建的静态库
        COMMAND cp -raf ${CMAKE_CURRENT_BINARY_DIR}/${STATIC_LIB_NAME} ${lib_path}
        # 复制所有头文件到公共库目录
        COMMAND cp -f ${CMAKE_CURRENT_SOURCE_DIR}/include/*.h ${lib_path}
        # 复制D-Bus生成的头文件到公共库目录
        COMMAND cp -f ${CMAKE_CURRENT_BINARY_DIR}/generated/rolling-helper-gdbus-generated.h ${lib_path}
        DEPENDS rolling_config_service_${CONFIG_VERSION_STRING}
        COMMENT "Config service build lib successfully"
    )
endif()

