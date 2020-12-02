#!/bin/bash

GIT_REV=$1

CMAKE_FLAGS="-DCMAKE_INSTALL_PREFIX=${PREFIX} -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release"

if [[ "$target_platform" == linux* ]]; then
    # CFLAGS
    # JRG: Had to add -ldl to prevent linking errors (dlopen, etc)
    MINIMAL_CFLAGS+=" -O3 -ldl"
    CFLAGS+=" $MINIMAL_CFLAGS"
    CXXFLAGS+=" $MINIMAL_CFLAGS"
    LDFLAGS+=" $LDPATHFLAGS"

    # Use GCC
    CMAKE_FLAGS+=" -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX"

    # CUDA is enabled in these platforms
    if [[ "$target_platform" == linux-64 || "$target_platform" == linux-ppc64le ]]; then
        # CUDA_HOME is defined by nvcc metapackage
        CMAKE_FLAGS+=" -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_HOME}"
        # From: https://github.com/floydhub/dl-docker/issues/59
        CMAKE_FLAGS+=" -DCMAKE_LIBRARY_PATH=${CUDA_HOME}/lib64/stubs"
        # CUDA tests won't build, disable for now
        # See https://github.com/openmm/openmm/issues/2258#issuecomment-462223634
        CMAKE_FLAGS+=" -DOPENMM_BUILD_CUDA_TESTS=OFF"
    fi

    # OpenCL ICD
    CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include/"
    CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"

elif [[ "$target_platform" == osx* ]]; then
    CMAKE_FLAGS+=" -DCMAKE_OSX_SYSROOT=${CONDA_BUILD_SYSROOT}"
    CMAKE_FLAGS+=" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
    CMAKE_FLAGS+=" -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}"
    if [[ "$opencl_impl" == khronos ]]; then
        CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include"
        CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"
    fi
    # When using opencl_impl == apple, CMake will auto-locate it, so no need to provide the flags
    # On Conda Forge, this will result in:
    #   /Applications/Xcode_12.app/Contents/Developer/Platforms/MacOSX.platform/Developer/...
    #   ...SDKs/MacOSX10.9.sdk/System/Library/Frameworks/OpenCL.framework
    # On local builds, it might be:
    #   /System/Library/Frameworks/OpenCL.framework/OpenCL
fi

# Set location for FFTW3 on both linux and mac
CMAKE_FLAGS+=" -DFFTW_INCLUDES=${PREFIX}/include/"
CMAKE_FLAGS+=" -DFFTW_LIBRARY=${PREFIX}/lib/libfftw3f${SHLIB_EXT}"
CMAKE_FLAGS+=" -DFFTW_THREADS_LIBRARY=${PREFIX}/lib/libfftw3f_threads${SHLIB_EXT}"

# Build in subdirectory and install.
mkdir -p build
cd build
cmake ${CMAKE_FLAGS} ${SRC_DIR}
make -j$CPU_COUNT
make -j$CPU_COUNT install PythonInstall

# Put examples into an appropriate subdirectory.
mkdir -p ${PREFIX}/share/openmm/
mv ${PREFIX}/examples ${PREFIX}/share/openmm/

# Patch git_revision in simtk.openmm.version
sed -i "s/git_revision = '[a-z0-9]+'/git_revision = \"${GIT_REV}\"/" ${SP_DIR}/simtk/openmm/version.py

# Fix some overlinking warnings/errors
for lib in ${PREFIX}/lib/plugins/*${SHLIB_EXT}; do
    ln -s $lib ${PREFIX}/lib/$(basename $lib) || true
done