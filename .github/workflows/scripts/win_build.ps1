# Build script for windows

param (
    [switch]$clone = $false,
    [switch]$installVulkan = $false,
    [switch]$develop = $false,
    [switch]$install = $false,
    [string]$libsDir = "."
)

$RepoURL = 'https://github.com/taichi-dev/taichi'

function WriteInfo($text) {
    Write-Host -ForegroundColor Green "[BUILD] $text"
}

# Get sccache
$env:SCCACHE_DIR="${pwd}/sccache_cache"
$env:SCCACHE_CACHE_SIZE="128M"
$env:SCCACHE_LOG="error"
$env:SCCACHE_ERROR_LOG="${pwd}/sccache_error.log"
WriteInfo("sccache dir: $Env:SCCACHE_DIR")
md "$Env:SCCACHE_DIR" -ea 0
if (-not (Test-Path "sccache-v0.2.15-x86_64-pc-windows-msvc")) {
    curl.exe --retry 10 --retry-delay 5 https://github.com/mozilla/sccache/releases/download/v0.2.15/sccache-v0.2.15-x86_64-pc-windows-msvc.tar.gz -LO
    tar -xzf sccache-v0.2.15-x86_64-pc-windows-msvc.tar.gz
    $env:PATH += ";${pwd}/sccache-v0.2.15-x86_64-pc-windows-msvc"
}
sccache -s

# WriteInfo("Install 7Zip")
# Install-Module 7Zip4PowerShell -Force -Verbose -Scope CurrentUser

if ($clone) {
    WriteInfo("Clone the repository")
    git clone --recurse-submodules $RepoURL
    Set-Location .\taichi
}

$libsDir = (Resolve-Path $libsDir).Path

if (-not (Test-Path $libsDir)) {
    New-Item -ItemType Directory -Path $libsDir
}
Push-Location $libsDir
WriteInfo("Download and extract LLVM")
if (-not (Test-Path "taichi_llvm")) {
    curl.exe --retry 10 --retry-delay 5 https://github.com/taichi-dev/taichi_assets/releases/download/llvm10/taichi-llvm-10.0.0-msvc2019.zip -LO
    7z x taichi-llvm-10.0.0-msvc2019.zip -otaichi_llvm
}
WriteInfo("Download and extract Clang")
if (-not (Test-Path "taichi_clang")) {
    curl.exe --retry 10 --retry-delay 5 https://github.com/taichi-dev/taichi_assets/releases/download/llvm10/clang-10.0.0-win.zip -LO
    7z x clang-10.0.0-win.zip -otaichi_clang
}
$env:LLVM_DIR = "$libsDir\taichi_llvm"
$env:TAICHI_CMAKE_ARGS = "-DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang"
$env:TAICHI_CMAKE_ARGS += " -DCMAKE_C_COMPILER_LAUNCHER=sccache -DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
if ($installVulkan) {
    WriteInfo("Download and install Vulkan")
    if (-not (Test-Path "VulkanSDK.exe")) {
        curl.exe --retry 10 --retry-delay 5 https://sdk.lunarg.com/sdk/download/1.2.189.0/windows/VulkanSDK-1.2.189.0-Installer.exe -Lo VulkanSDK.exe
    }
    $installer = Start-Process -FilePath VulkanSDK.exe -Wait -PassThru -ArgumentList @("/S");
    $installer.WaitForExit();
    $env:VULKAN_SDK = "$libsDir\VulkanSDK\1.2.189.0"
    $env:PATH += ";$env:VULKAN_SDK\Bin"
    $env:TAICHI_CMAKE_ARGS += " -DTI_WITH_VULKAN:BOOL=ON"
}

Pop-Location
clang --version

WriteInfo("Setting up Python environment")
python -m venv venv
. venv\Scripts\activate.ps1
python -m pip install wheel
python -m pip install -r requirements_dev.txt
python -m pip install -r requirements_test.txt
WriteInfo("Building Taichi")
$env:CLANG_EXECUTABLE = "$libsDir\taichi_clang\bin\clang++.exe"
$env:LLVM_AS_EXECUTABLE = "$libsDir\taichi_llvm\bin\llvm-as.exe"
if ($install) {
    if ($develop) {
        python -m pip install -v -e .
    } else {
        python -m pip install -v .
    }
    WriteInfo("Build and install finished")
} else {
    if ($env:PROJECT_NAME -eq "taichi-nightly") {
        python setup.py egg_info --tag-date bdist_wheel
    } else {
        python setup.py bdist_wheel
    }
    WriteInfo("Build finished")
}
