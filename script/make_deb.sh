#! /bin/bash
# Get the directory where the script is located, then switch to the project root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."
PROJECT_ROOT="$(pwd)"
build_path="$PROJECT_ROOT"
project_list=("rw101")
oem_list=("lenovo" "generic")

# Manually set the build_by_lib parameter, 1 means compile using library, 0 means normal compilation
# Users can directly modify this value to control the compilation method
build_by_lib=1

function make_project()
{
    current_path="$PROJECT_ROOT"
    # Check if binary_deb/common_lib directory needs to be preserved
    if [ -d "binary_deb" ]; then
        if [ "$build_by_lib" -eq 1 ] && [ -d "binary_deb/common_lib" ]; then
            # When build_by_lib is 1 and common_lib directory exists, only clear other files in binary_deb, preserve common_lib directory
            echo "build_by_lib is 1 and common_lib directory exists, preserving common_lib directory"
            # List all files and directories in binary_deb, exclude common_lib, then delete
            find binary_deb -mindepth 1 -maxdepth 1 -not -name "common_lib" -exec rm -rf {} \;
        else
            # In other cases, completely clear binary_deb directory
            rm -rf binary_deb
            mkdir ${current_path}/binary_deb
        fi
    else
        # If binary_deb directory doesn't exist, create it
        mkdir ${current_path}/binary_deb
    fi
    if [ $# -eq 2 ]; then
        if [ -d "build" ]; then
            rm -rf build
        fi
        cmake -S . -B build -DPROJECT_BUILD=$1 -DOEM_BUILD=$2 -DBUILD_BY_LIB=$build_by_lib
        cmake --build build
        cd build
        cpack
        mv *.deb ${current_path}/binary_deb/
        cd ../
    elif [ $# -eq 3 ]; then
        if [ -d "build" ]; then
            rm -rf build
        fi
        if [ "deb" == "$1" ]; then
            cmake -S . -B build -DBUILD_DEB=yes -DPROJECT_BUILD=$2 -DOEM_BUILD=$3 -DBUILD_BY_LIB=$build_by_lib
        elif [ "rpm" == "$1" ]; then
            cmake -S . -B build -DBUILD_RPM=yes -DPROJECT_BUILD=$2 -DOEM_BUILD=$3 -DBUILD_BY_LIB=$build_by_lib
        fi
        cmake --build build
        cd build
        cpack
        if [ "deb" == "$1" ]; then
            mv *.deb ${current_path}/binary_deb/
        elif [ "rpm" == "$1" ]; then
            mv *.rpm ${current_path}/binary_deb/
        fi
        cd ../

    else
        for project in "${project_list[@]}"; do
            for oem in "${oem_list[@]}"; do
                if [ -d "build" ]; then
                    rm -rf build
                fi
                cmake -S . -B build -DPROJECT_BUILD=${project} -DOEM_BUILD=${oem} -DBUILD_BY_LIB=$build_by_lib
                cmake --build build
                cd build
                cpack
                mv *.deb ${current_path}/binary_deb/
                cd ../

                cmake -S . -B build -DBUILD_PACKAGE=rpm -DPROJECT_BUILD=${project} -DOEM_BUILD=${oem} -DBUILD_BY_LIB=$build_by_lib
                cmake --build build
                cd build
                cpack
                mv *.rpm ${current_path}/binary_deb/
                cd ../
            done
        done
    fi
}

function make_biny_lib()
{
    current_path="$PROJECT_ROOT"
    if [ -d "build" ]; then
        rm -rf build
    fi
    if [ -d "binary_deb" ]; then
        rm -rf binary_deb
    fi
    mkdir ${current_path}/binary_deb

    if [ $# -eq 2 ]; then
        
        cmake -S . -B build -DBUILD_LIB=yes -DPROJECT_BUILD=$1 -DOEM_BUILD=$2
        cmake --build build
        cd build
        make helper_build_lib
        make flash_build_lib
        make config_build_lib
        make ma_build_lib
        cp -raf common_lib ${current_path}/binary_deb/
    else
        for project in "${project_list[@]}"; do
            for oem in "${oem_list[@]}"; do
                if [ -d "build" ]; then
                    rm -rf build
                fi
                cmake -S . -B build -DBUILD_LIB=yes -DPROJECT_BUILD=${project} -DOEM_BUILD=${oem}
                cmake --build build
                cd build
                make helper_build_lib
                make flash_build_lib
                make config_build_lib
                make ma_build_lib
                cp -raf common_lib ${current_path}/binary_deb/
                cd ../
            done
        done
    fi
}

function modify_apps_version()
{
    version="$1"
    awk -v version="$version" '
    {
        if ($0 ~ /project\(rolling_linux VERSION .*\)/) {
            gsub(/project\(rolling_linux VERSION .*\)/, "project(rolling_linux VERSION " version ")")
        }
        print
    }
    ' ${build_path}/../CMakeLists.txt > ${build_path}/../tmp 
    mv ${build_path}/../tmp ${build_path}/../CMakeLists.txt
}
if [[ "deb" == "$1" ]] || [[ "rpm" == "$1" ]]; then
    if [ $# -eq 3 ]; then
        if [ "deb" == "$1" ]; then
            make_project $1 $2 $3
        elif [ "rpm" == "$1" ]; then
            make_project $1 $2 $3
        fi
    elif [ $# -eq 4 ]; then
        version_regex='^[0-9]+\.[0-9]+'
        if [[ $4 =~ $version_regex ]]; then
            modify_apps_version $4
        fi
        make_project $1 $2 $3
    else
        make_project
    fi
elif [ "lib" == "$1" ]; then
    if [ $# -eq 3 ]; then
         make_biny_lib $2 $3
    else
        make_biny_lib
    fi
else
    echo  -e "para error,for example, you can send cmd to build deb
     \033[1;31m ./make_deb.sh deb rw101 lenovo
     \033[0;30m or you can send cmd build helper lib"
fi
