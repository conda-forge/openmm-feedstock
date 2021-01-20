#!/bin/bash
set -ex
with_cuda="no"

# Existence tests
test -f $PREFIX/lib/libOpenMM$SHLIB_EXT  # [unix]
test -f $PREFIX/lib/plugins/libOpenMMCPU$SHLIB_EXT  # [unix]
test -f $PREFIX/lib/plugins/libOpenMMPME$SHLIB_EXT  # [unix]
test -f $PREFIX/lib/plugins/libOpenMMOpenCL$SHLIB_EXT  # [unix]
if [[ "$target_platform" == linux-64 || "$target_platform" == linux-ppc64le ]]; then
    with_cuda="yes"
    test -f $PREFIX/lib/plugins/libOpenMMCUDA$SHLIB_EXT
    test -f $PREFIX/lib/plugins/libOpenMMCudaCompiler$SHLIB_EXT
fi

## Do they work properly?
# Debug silent errors in plugin loading
python -c "import simtk.openmm as mm; print('---Loaded---', *mm.pluginLoadedLibNames, '---Failed---', *mm.Platform.getPluginLoadFailures(), sep='\n')"
# Check that hardcoded library path was correctly replaced by conda-build
python -c "import os, simtk.openmm.version as v; print(v.openmm_library_path); assert os.path.isdir(v.openmm_library_path), 'Directory does not exist'"

# Check all platforms
python -m simtk.testInstallation
if [[ $with_cuda == yes ]]; then
    # Linux64 / PPC see all 4 platforms, but CUDA is not usable because there's no GPU there
    n_platforms=4
else
    # MacOS / ARM only see 3 because CUDA is not available there
    n_platforms=3
fi
python -c "from simtk.openmm import Platform as P; n = P.getNumPlatforms(); assert n == $n_platforms, f'n_platforms ({n}) != $n_platforms'"

# Run a small MD
cd ${PREFIX}/share/openmm/examples
python benchmark.py --test=rf --seconds=10 --platform=Reference
python benchmark.py --test=rf --seconds=10 --platform=CPU
if [[ -z ${CI-} ]]; then
    python benchmark.py --test=rf --seconds=10 --platform=OpenCL
    if [[ $with_cuda == yes ]]; then
        python benchmark.py --test=rf --seconds=10 --platform=CUDA
    fi
fi

# Check version metadata looks ok
python -c "from simtk.openmm import Platform; v = Platform.getOpenMMVersion(); assert \"$PKG_VERSION\" in (v, v+'.0'), v + \"!=$PKG_VERSION\""
python -c "from simtk.openmm.version import git_revision; r = git_revision; assert r == \"$GIT_FULL_HASH\", r + \"!=$GIT_FULL_HASH\""

if [[ $with_test_suite == "true" ]]; then
    cd $PREFIX/share/openmm/tests
    set +ex

    # C++ tests
    summary=""; exitcode=0; count=0;
    for f in Test*; do
        if [[ -n ${CI-} && ( $f == *Cuda* || $f == *OpenCL* ) ]]; then
            continue;
        fi
        ((count+=1))
        echo -e "\n#$count: $f"
        ./${f}
        thisexitcode=$?
        if [[ $thisexitcode != 0 ]]; then summary+="\n#$count ${f}: FAILED"; fi
        ((exitcode+=$thisexitcode))
    done
    echo "-------"
    echo "Summary"
    echo "-------"
    echo -e "${summary}"
    if [[ $exitcode != 0 ]]; then exit $exitcode; fi

    # Python tests
    set -ex
    cd python
    python -m pytest -v -n $CPU_COUNT
fi
