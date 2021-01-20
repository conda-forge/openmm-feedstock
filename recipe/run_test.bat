@echo on

:: Existence tests
if not exist %LIBRARY_LIB%/OpenMM.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMCPU.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMPME.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMOpenCL.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMCUDA.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMCudaCompiler.lib exit 1

:: Debug silent errors in plugin loading
python -c "import simtk.openmm as mm; print('---Loaded---', *mm.pluginLoadedLibNames, '---Failed---', *mm.Platform.getPluginLoadFailures(), sep='\n')"

:: Check that hardcoded library path was correctly replaced by conda-build
python -c "import os, simtk.openmm.version as v; print(v.openmm_library_path); assert os.path.isdir(v.openmm_library_path), 'Directory does not exist'" || goto :error

:: Check all platforms
python -m simtk.testInstallation

:: On CI, Windows will only see 2 platforms because the driver nvcuda.dll is missing and that throws a 126 error
:: We expect that people running this locally will have Nvidia properly installed, so they should all platforms (4)
if defined CI (
    set n_platforms=2
) else (
    set n_platforms=4
)
python -c "from simtk.openmm import Platform as P; n = P.getNumPlatforms(); assert n == %n_platforms%, f'n_platforms ({n}) != %n_platforms%'" || goto :error

:: Now let's run a little MD
cd %LIBRARY_PREFIX%/share/openmm/examples
python benchmark.py --test=rf --seconds=10 --platform=Reference || goto :error
python benchmark.py --test=rf --seconds=10 --platform=CPU || goto :error
if not defined CI (
    python benchmark.py --test=rf --seconds=10 --platform=CUDA  || goto :error
    python benchmark.py --test=rf --seconds=10 --platform=OpenCL  || goto :error

)

:: Check version metadata looks ok
python -c "from simtk.openmm import Platform; v = Platform.getOpenMMVersion(); assert '%PKG_VERSION%' in (v, v+'.0'), v + '!=%PKG_VERSION%'"  || goto :error
python -c "from simtk.openmm.version import git_revision; r = git_revision; assert r == '%GIT_FULL_HASH%', r + '!=%GIT_FULL_HASH%'" || goto :error


(set \n=^
%=This hack is required to store newlines=%
)

:: Run the full test suite, if requested
if "%with_test_suite%"=="true" (
    SETLOCAL EnableDelayedExpansion

    cd %LIBRARY_PREFIX%\share\openmm\tests

    :: Start with C++ tests
    set count=0
    set exitcode=0
    set summary=
    FOR %%F IN ( Test* ) do (
        set testexe=%%~F
        if defined CI (
            if not "x!testexe:Cuda=!"=="x!testexe!"   ( set skiptest=yes )
            if not "x!testexe:OpenCL=!"=="x!testexe!" ( set skiptest=yes )
        )
        if not defined skiptest (
            set /a count=!count!+1
            echo;
            echo #!count!: !testexe!
            .\!testexe!
            set thisexitcode=!errorlevel!
            set summary=!summary!
            if not "!thisexitcode!"=="0" ( set "summary=!summary!#!count! !testexe!: FAILED\n!" )
            set /a exitcode=!exitcode!+!thisexitcode!
        )
    )
    echo;
    echo --------------------
    echo Summary of run tests
    echo --------------------
    echo;
    echo !summary!
    if not "!exitcode!"=="0" goto :error

    :: Python unit tests
    cd python
    python -m pytest -v -n %CPU_COUNT% || goto :error

    ENDLOCAL
)

goto :EOF

:error
echo Failed with error #%errorlevel%.
exit /b %errorlevel%