@echo on

:: Are we running on CI? CONFIG is defined for the whole Azure pipeline
:: and we are bringing it in through `script_env` in meta.yaml
if not "%CONFIG%"=="" set CI="True"

:: Existence tests
if not exist %LIBRARY_LIB%/OpenMM.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMCPU.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMPME.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMOpenCL.lib exit 1
if not exist %LIBRARY_LIB%/plugins/OpenMMCUDA.lib exit 1

:: Debug silent errors in plugin loading
python -c "import openmm as mm; print('---Loaded---', *mm.pluginLoadedLibNames, '---Failed---', *mm.Platform.getPluginLoadFailures(), sep='\n')"

:: Check that hardcoded library path was correctly replaced by conda-build
python -c "import os, openmm.version as v; print(v.openmm_library_path); assert os.path.isdir(v.openmm_library_path), 'Directory does not exist'" || goto :error

:: Check all platforms
python -m openmm.testInstallation

:: On CI, Windows will only see 2 platforms because the driver nvcuda.dll is missing and that throws a 126 error
:: We expect that people running this locally will have Nvidia properly installed, so they should all platforms (4)
if "%CI%"=="" (
    set n_platforms=4
) else (
    set n_platforms=2
)
python -c "from openmm import Platform as P; n = P.getNumPlatforms(); assert n == %n_platforms%, f'n_platforms ({n}) != %n_platforms%'" || goto :error

:: Now let's run a little MD
cd %LIBRARY_PREFIX%/share/openmm/examples
python benchmark.py --test=rf --seconds=10 --platform=Reference || goto :error
python benchmark.py --test=rf --seconds=10 --platform=CPU || goto :error
if "%CI%"=="" (
    python benchmark.py --test=rf --seconds=10 --platform=CUDA  || goto :error
    python benchmark.py --test=rf --seconds=10 --platform=OpenCL  || goto :error
)

:: Check version metadata looks ok, only for final releases, RCs are not checked!
:: See https://stackoverflow.com/a/7006016/3407590 for substring checks in CMD
if x%PKG_VERSION:rc=%==x%PKG_VERSION% (
    if x%PKG_VERSION:beta=%==x%PKG_VERSION% (
	if x%PKG_VERSION:dev=%==x%PKG_VERSION% (
            python -c "from openmm import Platform; v = Platform.getOpenMMVersion(); assert '%PKG_VERSION%' in (v, v+'.0'), v + '!=%PKG_VERSION%'"  || goto :error
            for /f "usebackq tokens=1" %%a in (`git ls-remote https://github.com/openmm/openmm.git %PKG_VERSION%`) do (
            python -c "from openmm.version import git_revision; r = git_revision; assert r == '%%a', r + '!=%%a'" || goto :error
         )
	)
    )
) else (
    echo "!!! WARNING !!!"
    echo "This is a release candidate build (%PKG_VERSION%). Please check versions and git hashes manually!"
)


(set \n=^
%=This hack is required to store newlines=%
)

:: Run the full test suite, if requested
if "%with_test_suite%"=="true" (
    SETLOCAL EnableDelayedExpansion
    @echo off
    cd %LIBRARY_PREFIX%\share\openmm\tests

    :: Start with C++ tests
    if not "%CI%"=="" (
        del /Q /F TestCuda* TestOpenCL*
    )
    set count=0
    set exitcode=0
    set summary=
    FOR %%F IN ( Test* ) do (
        set testexe=%%~F
        set /a count=!count!+1
        echo;
        echo #!count!: !testexe!
        .\!testexe!
        set thisexitcode=!errorlevel!
        set summary=!summary!
        if not "!thisexitcode!"=="0" ( set "summary=!summary!#!count! !testexe!\n!" )
        set /a exitcode=!exitcode!+!thisexitcode!
    )
    if not "!exitcode!"=="0" (
        echo;
        echo ------------
        echo Failed tests
        echo ------------
        echo;
        echo !summary!
        exit /b !exitcode!
    )
    @echo on
    :: Python unit tests
    cd python
    python -m pytest -v -n %CPU_COUNT% || goto :error

    ENDLOCAL
)

goto :EOF

:error
echo Failed with error #%errorlevel%.
exit /b %errorlevel%
