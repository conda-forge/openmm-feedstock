mkdir build
cd build

set "CUDA_TOOLKIT_ROOT_DIR=%CUDA_PATH:\=/%"

cmake.exe .. -G "NMake Makefiles JOM" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DCUDA_TOOLKIT_ROOT_DIR="%CUDA_PATH%" ^
    -DOPENCL_INCLUDE_DIR="%LIBRARY_INC%" ^
    -DOPENCL_LIBRARY="%LIBRARY_LIB%\opencl.lib" ^
    -DBUILD_TESTING=OFF ^
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

goto :EOF

:error
echo Failed with error #%errorlevel%.
exit /b %errorlevel%