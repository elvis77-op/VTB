cmake_minimum_required(VERSION 3.10)
project(InitrdPackager)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/output)
file(MAKE_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY})

add_custom_target(initrd
    COMMAND ${CMAKE_COMMAND} -E make_directory 
        ${CMAKE_SOURCE_DIR}/rootfs/bin
        ${CMAKE_SOURCE_DIR}/rootfs/lib
        ${CMAKE_SOURCE_DIR}/rootfs/lib64
        ${CMAKE_SOURCE_DIR}/rootfs/dev
        ${CMAKE_SOURCE_DIR}/rootfs/proc
        ${CMAKE_SOURCE_DIR}/rootfs/sys
        ${CMAKE_SOURCE_DIR}/rootfs/run

    COMMAND ${CMAKE_COMMAND} 
        -S ${CMAKE_SOURCE_DIR}/src 
        -B ${CMAKE_SOURCE_DIR}/src/build 
        -DCMAKE_INSTALL_PREFIX=${CMAKE_SOURCE_DIR}/rootfs
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_SOURCE_DIR}/src/build --target install

    COMMAND bash ${CMAKE_SOURCE_DIR}/scripts/build_socat.sh ${CMAKE_SOURCE_DIR}

    COMMAND bash ${CMAKE_SOURCE_DIR}/scripts/pack_initrd.sh ${CMAKE_SOURCE_DIR}

    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    
    COMMENT "Building Isolated Initrd Environment..."

    COMMAND env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ${CMAKE_SOURCE_DIR}/scripts/pack_initrd.sh ${CMAKE_SOURCE_DIR}

    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    
    COMMENT "Building Isolated Initrd Environment..."
)