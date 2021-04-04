@echo on

mkdir build
cd build

set "CUDA_TOOLKIT_ROOT_DIR=%CUDA_PATH:\=/%"

if "%with_test_suite%"=="true" (
    set "CMAKE_FLAGS=-DBUILD_TESTING=ON  -DOPENMM_BUILD_CUDA_TESTS=ON  -DOPENMM_BUILD_OPENCL_TESTS=ON"
) else (
    set "CMAKE_FLAGS=-DBUILD_TESTING=OFF -DOPENMM_BUILD_CUDA_TESTS=OFF -DOPENMM_BUILD_OPENCL_TESTS=OFF"
)

cmake.exe .. -G "NMake Makefiles JOM" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DCUDA_TOOLKIT_ROOT_DIR="%CUDA_TOOLKIT_ROOT_DIR%" ^
    -DOPENCL_INCLUDE_DIR="%LIBRARY_INC%" ^
    -DOPENCL_LIBRARY="%LIBRARY_LIB%\opencl.lib" ^
    %CMAKE_FLAGS% ^
    || goto :error

jom -j %NUMBER_OF_PROCESSORS% || goto :error
jom -j %NUMBER_OF_PROCESSORS% install || goto :error
jom -j %NUMBER_OF_PROCESSORS% PythonInstall || goto :error

:: Better location for examples
mkdir %LIBRARY_PREFIX%\share\openmm || goto :error
move %LIBRARY_PREFIX%\examples %LIBRARY_PREFIX%\share\openmm || goto :error

if "%with_test_suite%"=="true" (
    mkdir %LIBRARY_PREFIX%\share\openmm\tests\ || goto :error
    find . -name "Test*" -type f -exec cp "{}" %LIBRARY_PREFIX%\share\openmm\tests\ ; || goto :error
    robocopy /E python\tests\ %LIBRARY_PREFIX%\share\openmm\tests\python
    if %errorlevel% GTR 1 ( exit /b %errorlevel% )
)


goto :EOF

:error
echo Failed with error #%errorlevel%.
exit /b %errorlevel%
