mkdir build
cd build

set "CUDA_TOOLKIT_ROOT_DIR=%CUDA_PATH:\=/%"

if "%with_test_suite%"=="true" (
    CMAKE_FLAGS="-DBUILD_TESTING=ON -DOPENMM_BUILD_CUDA_TESTS=OFF -DOPENMM_BUILD_OPENCL_TESTS=OFF"
)
else (
    CMAKE_FLAGS="-DBUILD_TESTING=OFF"
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

:: Workaround overlinking warnings
@REM copy %SP_DIR%\simtk\openmm\_openmm* %LIBRARY_BIN% || goto :error
@REM copy %LIBRARY_LIB%\OpenMM* %LIBRARY_BIN% || goto :error
@REM copy %LIBRARY_LIB%\plugins\OpenMM* %LIBRARY_BIN% || goto :error

:: Better location for examples
mkdir %LIBRARY_PREFIX%\share\openmm || goto :error
move %LIBRARY_PREFIX%\examples %LIBRARY_PREFIX%\share\openmm || goto :error

if "%with_test_suite%"=="true" (
    cd ..
    mkdir %LIBRARY_PREFIX%\share\openmm\tests
    mv build %LIBRARY_PREFIX%\share\openmm\tests
)


goto :EOF

:error
echo Failed with error #%errorlevel%.
exit /b %errorlevel%
