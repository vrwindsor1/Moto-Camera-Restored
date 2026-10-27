# ==============================================================================
# Moto Camera Restored -- Universal Recovery Package Compiler (Windows PowerShell)
# Modular Multi-Generation Motorola Camera Restoration Toolkit
#
# Supported Camera Eras:
#   * Moto Camera 4 (Working -- template active)
#   * Moto Camera 5 (In Development)
#   * Moto Camera 3 (Planned)
#   * Moto Camera 2 (Planned)
#
# Target Systems: LineageOS, AOSP, and custom ROMs (Android 13 - 17+)
#
# Generates:
#   MotoCameraRestored_<Codename>_Recovery_Installer.zip (Lineage Recovery / TWRP sideload)
#   with LineageOS addon.d OTA backup survival script
#
# Usage:
#   Interactive:  .\compile_recovery_package_windows.ps1
#   CLI:          .\compile_recovery_package_windows.ps1 -FirmwarePath "C:\path\to\stock_firmware" [-OutputDir "C:\output"] [-TemplateDir "C:\path\to\templates"]
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$FirmwarePath,

    [Parameter(Position=1)]
    [string]$OutputDir,

    [Parameter(Position=2)]
    [string]$TemplateDir
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GitHubRawBase = "https://raw.githubusercontent.com/vrwindsor1/Moto-Camera-Restored/main"

if (-not $OutputDir) {
    $OutputDir = Join-Path $ScriptDir "output"
}

# --- Colorized Logging ---
function Write-Header {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "        Moto Camera Restored -- Universal Recovery Package Compiler             " -ForegroundColor Cyan
    Write-Host "         Modular Dynamic Multi-Generation Camera Extraction Toolkit             " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "               * Pair Programmed with Google DeepMind Antigravity               " -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Log-Info([string]$msg)    { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Log-Ok([string]$msg)      { Write-Host "[OK] $msg" -ForegroundColor Green }
function Log-Warn([string]$msg)    { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Log-Err([string]$msg)     { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Log-Profile([string]$msg) { Write-Host "[PROFILE] $msg" -ForegroundColor Magenta }

# Helper: Copy single file safely
function Copy-BlobFile([string]$Source, [string]$DestinationDir) {
    if (Test-Path $Source) {
        if (-not (Test-Path $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }
        Copy-Item -Path $Source -Destination $DestinationDir -Force
    }
}

# Helper: Copy directory tree safely
function Copy-BlobDir([string]$SourceDir, [string]$DestinationDir) {
    if (Test-Path $SourceDir) {
        if (-not (Test-Path $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }
        Copy-Item -Path $SourceDir -Destination $DestinationDir -Recurse -Force
    }
}

# Helper: Copy files matching wildcard safely
function Copy-BlobPattern([string]$SourcePattern, [string]$DestinationDir) {
    $items = Get-ChildItem -Path $SourcePattern -ErrorAction SilentlyContinue
    if ($items) {
        if (-not (Test-Path $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }
        foreach ($item in $items) {
            Copy-Item -Path $item.FullName -Destination $DestinationDir -Force
        }
    }
}

# Helper: Read property from list of build.prop files
function Get-BuildProp([string]$Key, [string[]]$PropFiles) {
    foreach ($file in $PropFiles) {
        if (Test-Path $file) {
            $line = Get-Content -Path $file -ErrorAction SilentlyContinue | Where-Object { $_ -match "^$Key=(.*)$" } | Select-Object -First 1
            if ($line) {
                return $matches[1].Trim()
            }
        }
    }
    return $null
}

# Modular Template Resolution
function Ensure-Templates([string]$WorkDir, [string]$CameraGen, [string]$GenName, [string]$CliTemplate) {
    # 1. CLI-specified directory
    if ($CliTemplate) {
        $cleanCli = $CliTemplate.Trim().Trim('"').Trim("'")
        if (Test-Path $cleanCli) {
            $resolvedCli = (Resolve-Path $cleanCli).Path
            $candidatePath = $null
            if (Test-Path (Join-Path $resolvedCli "META-INF\com\google\android\update-binary")) {
                $candidatePath = $resolvedCli
            } elseif (Test-Path (Join-Path $resolvedCli "$CameraGen\META-INF\com\google\android\update-binary")) {
                $candidatePath = Join-Path $resolvedCli $CameraGen
            } elseif (Test-Path (Join-Path $resolvedCli "templates\$CameraGen\META-INF\com\google\android\update-binary")) {
                $candidatePath = Join-Path $resolvedCli "templates\$CameraGen"
            }

            if ($candidatePath) {
                Log-Ok "Using CLI-specified recovery templates from: $candidatePath"
                return $candidatePath
            } else {
                Log-Warn "CLI-specified template path '$cleanCli' does not contain required template files."
            }
        }
    }

    # 2. Local script directory check
    $localTemplatesDir = Join-Path $ScriptDir "templates\$CameraGen"
    if ((Test-Path $localTemplatesDir) -and (Test-Path (Join-Path $localTemplatesDir "META-INF\com\google\android\update-binary"))) {
        Log-Ok "Found local recovery templates for $GenName ($CameraGen)."
        return $localTemplatesDir
    }

    # 3. Current working directory check
    $cwdTemplatesDir = Join-Path (Get-Location) "templates\$CameraGen"
    if ((Test-Path $cwdTemplatesDir) -and (Test-Path (Join-Path $cwdTemplatesDir "META-INF\com\google\android\update-binary"))) {
        Log-Ok "Found local recovery templates for $GenName ($CameraGen)."
        return $cwdTemplatesDir
    }

    # 4. Template folder not present in working directory -> Prompt the user
    Log-Warn "Recovery template folder for $GenName ('templates\$CameraGen') was not found in working directory."
    Write-Host ""
    Write-Host "Please point to a local template directory, or press [Enter] to automatically download from GitHub:" -ForegroundColor White
    $userTemplateInput = Read-Host "> Local template path [Enter to download]"
    if ($userTemplateInput) {
        $userTemplateInput = $userTemplateInput.Trim().Trim('"').Trim("'")
    }

    if ($userTemplateInput -and (Test-Path $userTemplateInput)) {
        $resolvedUserPath = (Resolve-Path $userTemplateInput).Path
        $candidatePath = $null
        if (Test-Path (Join-Path $resolvedUserPath "META-INF\com\google\android\update-binary")) {
            $candidatePath = $resolvedUserPath
        } elseif (Test-Path (Join-Path $resolvedUserPath "$CameraGen\META-INF\com\google\android\update-binary")) {
            $candidatePath = Join-Path $resolvedUserPath $CameraGen
        } elseif (Test-Path (Join-Path $resolvedUserPath "templates\$CameraGen\META-INF\com\google\android\update-binary")) {
            $candidatePath = Join-Path $resolvedUserPath "templates\$CameraGen"
        }

        if ($candidatePath) {
            Log-Ok "Using user-specified recovery templates from: $candidatePath"
            return $candidatePath
        } else {
            Log-Warn "Specified directory did not contain valid recovery templates for $GenName."
            Log-Info "Proceeding with automatic download from GitHub..."
        }
    }

    # 5. Remote download from GitHub repository
    Log-Info "Downloading $GenName recovery templates from GitHub repository..."
    $downloadDir = Join-Path (Get-Location) "templates\$CameraGen"
    try {
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        }
    } catch {
        $downloadDir = Join-Path $WorkDir "templates\$CameraGen"
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    }

    New-Item -ItemType Directory -Path (Join-Path $downloadDir "META-INF\com\google\android") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $downloadDir "addon.d") -Force | Out-Null

    $files = @(
        "templates/$CameraGen/build.prop",
        "templates/$CameraGen/toybox",
        "templates/$CameraGen/addon.d/addond_head",
        "templates/$CameraGen/addon.d/addond_tail",
        "templates/$CameraGen/META-INF/com/google/android/update-binary",
        "templates/$CameraGen/META-INF/com/google/android/updater-script"
    )

    foreach ($file in $files) {
        $relDest = $file.Replace("templates/$CameraGen/", "").Replace('/', '\')
        $destPath = Join-Path $downloadDir $relDest
        $parentDir = Split-Path -Parent $destPath
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        
        $url = "$GitHubRawBase/$file"
        $fallbackUrl = $null
        if ($CameraGen -eq "camera4") {
            $fallbackUrl = "https://raw.githubusercontent.com/vrwindsor1/Universal_MotCamera4Suite_Installer/main/templates/recovery/" + $file.Replace("templates/$CameraGen/", "")
        }

        $dlOk = $false
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
            $dlOk = $true
        } catch {
            if ($fallbackUrl) {
                try {
                    Invoke-WebRequest -Uri $fallbackUrl -OutFile $destPath -UseBasicParsing
                    $dlOk = $true
                } catch {}
            }
        }

        if (-not $dlOk) {
            Log-Err "Failed to download required template file: $url"
            Write-Host ""
            Write-Host "[NOTE] The recovery template module '$CameraGen' ($GenName) is currently in development / not yet available." -ForegroundColor Yellow
            Write-Host "Currently active and working module: Moto Camera 4 ('camera4')." -ForegroundColor Gray
            Write-Host "Support for $GenName will be added in a future update." -ForegroundColor Gray
            exit 1
        }
    }

    Log-Ok "Recovery templates for $GenName successfully downloaded to: $downloadDir"
    return $downloadDir
}

# --- Main Flow ---
Write-Header

# 1. Prompt for Firmware Directory if not supplied
if (-not $FirmwarePath) {
    Write-Host "Please specify the path to your Motorola stock firmware:" -ForegroundColor White
    Write-Host "  (Accepts: pre-extracted folder containing product and system_ext, or your RSA folder)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Tip: Stock firmware can be downloaded via Motorola Software Fix (RSA) or from:" -ForegroundColor Cyan
    Write-Host "     https://mirrors.lolinet.com/firmware/lenomola/" -ForegroundColor Yellow
    Write-Host ""
    $FirmwarePath = Read-Host "> Path"
}

$FirmwarePath = $FirmwarePath.Trim().Trim('"').Trim("'")

if (-not (Test-Path $FirmwarePath)) {
    Log-Err "Specified path does not exist: $FirmwarePath"
    exit 1
}

$ResolvedFirmware = (Resolve-Path $FirmwarePath).Path
Log-Ok "Firmware source: $ResolvedFirmware"

# 2. Locate Partitions Root
$FirmwareRoot = $null
if ((Test-Path (Join-Path $ResolvedFirmware "product")) -and (Test-Path (Join-Path $ResolvedFirmware "system_ext"))) {
    $FirmwareRoot = $ResolvedFirmware
} else {
    $subDirs = Get-ChildItem -Path $ResolvedFirmware -Directory
    foreach ($sub in $subDirs) {
        if ((Test-Path (Join-Path $sub.FullName "product")) -and (Test-Path (Join-Path $sub.FullName "system_ext"))) {
            $FirmwareRoot = $sub.FullName
            break
        }
    }
}

if (-not $FirmwareRoot) {
    $sparseChunks = Get-ChildItem -Path $ResolvedFirmware -Filter "super.img_sparsechunk.*" -Recurse -ErrorAction SilentlyContinue
    if ($sparseChunks) {
        Log-Warn "Detected raw super.img_sparsechunks, but dynamic partition extraction is required."
        Write-Host ""
        Write-Host "On Windows, dynamic Android super partitions (sparsechunks) can be extracted via:" -ForegroundColor Yellow
        Write-Host "  1. Windows Subsystem for Linux (WSL):" -ForegroundColor White
        Write-Host "       wsl ./compile_recovery_package_linux.sh `"$ResolvedFirmware`"" -ForegroundColor Gray
        Write-Host "  2. 7-Zip (v23+ with EROFS plugin) or lpunpack/simg2img for Windows" -ForegroundColor White
        Write-Host ""
        Log-Err "Please point this script to the extracted directory containing 'product' and 'system_ext'."
        exit 1
    } else {
        Log-Err "Could not find 'product' and 'system_ext' directories in: $ResolvedFirmware"
        Log-Err "Please ensure the firmware partitions are extracted."
        exit 1
    }
}

Log-Ok "Partitions located at: $FirmwareRoot"

$sysPath = Join-Path $FirmwareRoot "system"
if (Test-Path (Join-Path $FirmwareRoot "system\system")) {
    $sysPath = Join-Path $FirmwareRoot "system\system"
}

# 3. Device Profiling and Metadata Discovery
Log-Info "Profiling device hardware and firmware properties..."
$propFiles = @(
    (Join-Path $FirmwareRoot "product\etc\build.prop"),
    (Join-Path $FirmwareRoot "product\build.prop"),
    (Join-Path $FirmwareRoot "vendor\build.prop"),
    (Join-Path $sysPath "build.prop"),
    (Join-Path $FirmwareRoot "system_ext\etc\build.prop"),
    (Join-Path $FirmwareRoot "system_ext\build.prop"),
    (Join-Path $FirmwareRoot "odm\etc\build.prop")
)

$DeviceCodename = Get-BuildProp "ro.product.vendor.device" $propFiles
if (-not $DeviceCodename) { $DeviceCodename = Get-BuildProp "ro.product.system.device" $propFiles }
if (-not $DeviceCodename) { $DeviceCodename = Get-BuildProp "ro.product.product.device" $propFiles }
if (-not $DeviceCodename) { $DeviceCodename = Get-BuildProp "ro.product.device" $propFiles }
if (-not $DeviceCodename) { $DeviceCodename = Get-BuildProp "ro.product.vendor.name" $propFiles }
if (-not $DeviceCodename) { $DeviceCodename = Get-BuildProp "ro.product.system.name" $propFiles }
if (-not $DeviceCodename) { $DeviceCodename = Get-BuildProp "ro.product.product.name" $propFiles }

if ((-not $DeviceCodename) -or ($DeviceCodename -eq "msi")) {
    $camPerm = Get-ChildItem -Path (Join-Path $FirmwareRoot "product\etc\permissions") -Filter "com.motorola.camera*.*.xml" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($camPerm) {
        $candidate = $camPerm.BaseName.Replace("com.motorola.camera3.", "").Replace("com.motorola.camera.", "").Replace("com.motorola.camera5.", "")
        if ($candidate -ne "content.ai" -and $candidate -ne "lens") {
            $DeviceCodename = $candidate
        }
    }
}
if (-not $DeviceCodename) { $DeviceCodename = "generic" }

$DeviceModel = Get-BuildProp "ro.product.product.model" $propFiles
if (-not $DeviceModel) { $DeviceModel = Get-BuildProp "ro.product.system.model" $propFiles }
if (-not $DeviceModel) { $DeviceModel = Get-BuildProp "ro.product.vendor.model" $propFiles }
if (-not $DeviceModel) { $DeviceModel = Get-BuildProp "ro.product.model" $propFiles }
if (-not $DeviceModel) { $DeviceModel = "Motorola Smartphone" }

$AndroidVersion = Get-BuildProp "ro.build.version.release" $propFiles
if (-not $AndroidVersion) { $AndroidVersion = Get-BuildProp "ro.product.build.version.release" $propFiles }
if (-not $AndroidVersion) { $AndroidVersion = "14" }

$SdkLevel = Get-BuildProp "ro.build.version.sdk" $propFiles
if (-not $SdkLevel) { $SdkLevel = Get-BuildProp "ro.product.build.version.sdk" $propFiles }
if (-not $SdkLevel) { $SdkLevel = "34" }

$BuildId = Get-BuildProp "ro.build.id" $propFiles
if (-not $BuildId) { $BuildId = Get-BuildProp "ro.product.build.id" $propFiles }
if (-not $BuildId) { $BuildId = "UNKNOWN" }

$PlatformSoc = Get-BuildProp "ro.board.platform" $propFiles
if (-not $PlatformSoc) { $PlatformSoc = Get-BuildProp "ro.hardware" $propFiles }
if (-not $PlatformSoc) { $PlatformSoc = "unknown" }

Log-Profile "Detected Stock Firmware Profile:"
Write-Host "    Model:       $DeviceModel" -ForegroundColor White
Write-Host "    Codename:    $DeviceCodename" -ForegroundColor White
Write-Host "    Platform:    $PlatformSoc" -ForegroundColor White
Write-Host "    Android:     $AndroidVersion (API SDK $SdkLevel)" -ForegroundColor White
Write-Host "    Build ID:    $BuildId" -ForegroundColor White

# 4. Modular Camera Generation Detection
Log-Info "Detecting stock Motorola Camera generation and components..."
$CameraGen = ""
$CameraGenName = ""
$MainCameraApk = $null
$CameraVer = ""

# 1. Camera 5 check
$cam5Apk = Get-ChildItem -Path $FirmwareRoot -Filter "*Camera5*.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cam5Apk) {
    $CameraGen = "camera5"
    $CameraGenName = "Moto Camera 5"
    $MainCameraApk = $cam5Apk
    $CameraVer = "v10.x"
}

# 2. Camera 4 check
if (-not $CameraGen) {
    $cam4Apk = Get-ChildItem -Path $FirmwareRoot -Filter "MotCamera4.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cam4Apk) {
        $CameraGen = "camera4"
        $CameraGenName = "Moto Camera 4"
        $MainCameraApk = $cam4Apk
    }
}

# 3. Camera 3 check
if (-not $CameraGen) {
    $cam3Apk = Get-ChildItem -Path $FirmwareRoot -Filter "MotCamera3.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cam3Apk) {
        $CameraGen = "camera3"
        $CameraGenName = "Moto Camera 3"
        $MainCameraApk = $cam3Apk
    }
}

# 4. Camera 2 check
if (-not $CameraGen) {
    $cam2Apk = Get-ChildItem -Path $FirmwareRoot -Filter "*Camera2*.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cam2Apk) {
        $CameraGen = "camera2"
        $CameraGenName = "Moto Camera 2"
        $MainCameraApk = $cam2Apk
    }
}

# Fallback heuristics
if (-not $CameraGen) {
    if ([int]$SdkLevel -ge 35) {
        $CameraGen = "camera5"; $CameraGenName = "Moto Camera 5"
    } elseif ([int]$SdkLevel -ge 31) {
        $CameraGen = "camera4"; $CameraGenName = "Moto Camera 4"
    } elseif ([int]$SdkLevel -ge 29) {
        $CameraGen = "camera3"; $CameraGenName = "Moto Camera 3"
    } else {
        $CameraGen = "camera2"; $CameraGenName = "Moto Camera 2"
    }
}

if (-not $CameraVer) { $CameraVer = $CameraGenName }

Log-Ok "Detected Camera Suite: $CameraGenName ($CameraVer)"
Log-Info "Active Template Module: $CameraGen"

# Check companion components
$aiApk = Get-ChildItem -Path $FirmwareRoot -Filter "MotCamera*AI*.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($aiApk) { Log-Ok "Found AI Scene Engine: $($aiApk.Name)" }
$tuningApk = Get-ChildItem -Path (Join-Path $FirmwareRoot "system_ext\priv-app") -Filter "ImagerTuning*.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($tuningApk) { Log-Ok "Found Image Tuning Provider: $($tuningApk.Name)" }
$desktopApk = Get-ChildItem -Path $FirmwareRoot -Filter "MotCameraDesktop.apk" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($desktopApk) { Log-Ok "Found Desktop Companion: MotCameraDesktop.apk" }

# 5. Create Temporary Staging Directory
$TempWorkDir = Join-Path $env:TEMP ("motocamera_build_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
$StagingDir = Join-Path $TempWorkDir "staging\system"
$RecBuildDir = Join-Path $TempWorkDir "recovery_build"

New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
New-Item -ItemType Directory -Path $RecBuildDir -Force | Out-Null

try {
    $TemplatesDir = Ensure-Templates $TempWorkDir $CameraGen $CameraGenName $TemplateDir

    # 6. Harvest Camera Properties into motocamera.prop
    Log-Info "Harvesting device-specific multi-camera system properties..."
    $propOut = Join-Path $TempWorkDir "motocamera.prop"
    $propLines = [System.Collections.Generic.List[string]]::new()
    $propLines.Add("# Motorola Camera Harvested Properties")
    $propLines.Add("ro.motocamera.device=$DeviceCodename")
    $propLines.Add("ro.motocamera.model=$DeviceModel")
    $propLines.Add("ro.motocamera.android=$AndroidVersion")
    $propLines.Add("ro.motocamera.sdk=$SdkLevel")
    $propLines.Add("ro.motocamera.build_id=$BuildId")
    $propLines.Add("ro.motocamera.generation=$CameraGen")
    $propLines.Add("ro.motocamera.version=$CameraVer")
    $propLines.Add("")

    $seenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pf in $propFiles) {
        if (Test-Path $pf) {
            $lines = Get-Content -Path $pf -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line -match "^(persist\.vendor\.camera\.[^=]+|vendor\.camera\.aux\.[^=]+|ro\.vendor\.camera\.aux\.[^=]+|ro\.camera\.cfa\.[^=]+|camera\.disable_zsl_mode|ro\.camera\.enableCamera1MaxZsl)=(.*)$") {
                    $k = $matches[1].Trim()
                    $v = $matches[2].Trim()
                    if (-not $seenKeys.Contains($k)) {
                        $seenKeys.Add($k) | Out-Null
                        $propLines.Add("$k=$v")
                    }
                }
            }
        }
    }

    if (-not $seenKeys.Contains("persist.vendor.camera.expose.aux")) {
        $propLines.Add("persist.vendor.camera.expose.aux=1")
    }

    [System.IO.File]::WriteAllLines($propOut, $propLines, [System.Text.Encoding]::ASCII)
    Log-Ok "Harvested $($seenKeys.Count) device camera properties."

    # 7. Harvest Proprietary Files
    Log-Info "Harvesting $CameraGenName binaries, libraries, and frameworks..."

    # Product Partition
    Log-Info "  - Harvesting Product applications and permissions..."
    if ($MainCameraApk) {
        $camParent = $MainCameraApk.Directory.FullName
        Copy-BlobDir $camParent (Join-Path $StagingDir ("product\priv-app\" + $MainCameraApk.Directory.Name))
    }

    if ($aiApk) {
        Copy-BlobDir $aiApk.Directory.FullName (Join-Path $StagingDir ("product\app\" + $aiApk.Directory.Name))
    }

    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\permissions\*com.motorola.camera*") (Join-Path $StagingDir "product\etc\permissions")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\sysconfig\*com.motorola.camera*") (Join-Path $StagingDir "product\etc\sysconfig")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\init\*motcamera*") (Join-Path $StagingDir "product\etc\init")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\MotoDesktopAppConfig\*") (Join-Path $StagingDir "product\etc\MotoDesktopAppConfig")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\media\audio\ui\camera_*") (Join-Path $StagingDir "product\media\audio\ui")

    # System_ext Partition
    Log-Info "  - Harvesting System_ext ImagerTuning, Desktop, frameworks, and libs..."
    $tuningDirs = Get-ChildItem -Path (Join-Path $FirmwareRoot "system_ext\priv-app") -Directory -Filter "ImagerTuning*" -ErrorAction SilentlyContinue
    foreach ($td in $tuningDirs) {
        Copy-BlobDir $td.FullName (Join-Path $StagingDir "system_ext\priv-app\$($td.Name)")
    }

    $deskDir = Join-Path $FirmwareRoot "system_ext\priv-app\MotCameraDesktop"
    if (Test-Path $deskDir) {
        Copy-BlobDir $deskDir (Join-Path $StagingDir "system_ext\priv-app\MotCameraDesktop")
    }

    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\framework\*com.motorola.*") (Join-Path $StagingDir "system_ext\framework")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\permissions\*motorola*") (Join-Path $StagingDir "system_ext\etc\permissions")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\permissions\*imager*") (Join-Path $StagingDir "system_ext\etc\permissions")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\permissions\*camera*") (Join-Path $StagingDir "system_ext\etc\permissions")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\public.libraries-*") (Join-Path $StagingDir "system_ext\etc")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\enable-disable-packages\*camera*") (Join-Path $StagingDir "system_ext\etc\enable-disable-packages")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\enable-disable-packages\*desktop*") (Join-Path $StagingDir "system_ext\etc\enable-disable-packages")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\sysconfig\*") (Join-Path $StagingDir "system_ext\etc\sysconfig")

    # System_ext native libraries
    foreach ($arch in @("lib64", "lib")) {
        $extLibDir = Join-Path $FirmwareRoot "system_ext\$arch"
        if (Test-Path $extLibDir) {
            foreach ($pattern in @("libarcsoft*", "libcamera*", "libimgTuner*", "libjni_helper*", "libopencv*", "motorola.hardware.camera*")) {
                Copy-BlobPattern (Join-Path $extLibDir "$pattern.so") (Join-Path $StagingDir "system_ext\$arch")
            }
        }
    }

    # System Framework and System Libraries
    Log-Info "  - Harvesting System framework signature libraries..."
    Copy-BlobFile (Join-Path $sysPath "framework\com.motorola.motosignature.jar") (Join-Path $StagingDir "system\framework")
    Copy-BlobFile (Join-Path $sysPath "framework\moto-core_services.jar") (Join-Path $StagingDir "system\framework")
    Copy-BlobFile (Join-Path $sysPath "framework\moto-settings.jar") (Join-Path $StagingDir "system\framework")
    Copy-BlobFile (Join-Path $sysPath "etc\permissions\com.motorola.motosignature.xml") (Join-Path $StagingDir "system\etc\permissions")
    Copy-BlobFile (Join-Path $sysPath "etc\permissions\moto-core_services.xml") (Join-Path $StagingDir "system\etc\permissions")
    Copy-BlobFile (Join-Path $sysPath "etc\permissions\moto-settings.xml") (Join-Path $StagingDir "system\etc\permissions")

    foreach ($arch in @("lib64", "lib")) {
        $sysLibDir = Join-Path $sysPath $arch
        if (Test-Path $sysLibDir) {
            Copy-BlobPattern (Join-Path $sysLibDir "motorola.hardware.camera*.so") (Join-Path $StagingDir "system\$arch")
        }
    }

    # Vendor Camera HAL and VINTF Manifest
    Log-Info "  - Harvesting Vendor HAL services and VINTF manifests..."
    Copy-BlobPattern (Join-Path $FirmwareRoot "vendor\bin\hw\motorola.hardware.camera.*") (Join-Path $StagingDir "system\vendor\bin\hw")
    Copy-BlobPattern (Join-Path $FirmwareRoot "vendor\etc\init\motorola.hardware.camera.*") (Join-Path $StagingDir "system\vendor\etc\init")
    
    foreach ($arch in @("lib64", "lib")) {
        Copy-BlobPattern (Join-Path $FirmwareRoot "vendor\$arch\hw\motorola.hardware.camera.*") (Join-Path $StagingDir "system\vendor\$arch\hw")
        Copy-BlobPattern (Join-Path $FirmwareRoot "vendor\$arch\motorola.hardware.camera.*") (Join-Path $StagingDir "system\vendor\$arch")
        Copy-BlobPattern (Join-Path $FirmwareRoot "vendor\$arch\libmot_chi_desktop_helper*") (Join-Path $StagingDir "system\vendor\$arch")
    }

    $vintfDest = Join-Path $StagingDir "system\vendor\etc\vintf\manifest\manifest_imgtuner.xml"
    $vintfSrc = Join-Path $FirmwareRoot "vendor\etc\vintf\manifest\manifest_imgtuner.xml"
    if (Test-Path $vintfSrc) {
        Copy-BlobFile $vintfSrc (Split-Path -Parent $vintfDest)
    } else {
        $vintfParent = Split-Path -Parent $vintfDest
        if (-not (Test-Path $vintfParent)) { New-Item -ItemType Directory -Path $vintfParent -Force | Out-Null }
        $manifestXml = @(
            '<manifest version="1.0" type="device">',
            '    <hal format="hidl">',
            '        <name>motorola.hardware.camera.imgtuner</name>',
            '        <transport>hwbinder</transport>',
            '        <version>1.0</version>',
            '        <version>2.0</version>',
            '        <interface>',
            '            <name>IImageTuning</name>',
            '            <instance>default</instance>',
            '        </interface>',
            '        <fqname>@1.0::IImageTuning/default</fqname>',
            '        <fqname>@2.0::IImageTuning/default</fqname>',
            '    </hal>',
            '</manifest>'
        ) -join [System.Environment]::NewLine
        Set-Content -Path $vintfDest -Value $manifestXml -Encoding ASCII
    }

    Log-Ok "All $CameraGenName proprietary blobs harvested successfully."

    # 8. Assemble Flashable Recovery Package
    Log-Info "Assembling flashable recovery installer for $DeviceModel ($DeviceCodename)..."
    Copy-Item -Path (Join-Path $TemplatesDir "*") -Destination $RecBuildDir -Recurse -Force

    # Write dynamic build.prop metadata
    $recBuildProp = @(
        "arch=arm64",
        "version=$SdkLevel",
        "version_nice=$AndroidVersion.0.0",
        "ro.product.device=$DeviceCodename",
        "ro.product.model=$DeviceModel"
    ) -join [System.Environment]::NewLine
    Set-Content -Path (Join-Path $RecBuildDir "build.prop") -Value $recBuildProp -Encoding ASCII

    # addon.d scripts
    $recSystemAddond = Join-Path $RecBuildDir "system\addon.d"
    New-Item -ItemType Directory -Path $recSystemAddond -Force | Out-Null
    Copy-Item -Path (Join-Path $TemplatesDir "addon.d\*") -Destination $recSystemAddond -Force
    if (Test-Path (Join-Path $RecBuildDir "addon.d")) {
        Remove-Item -Path (Join-Path $RecBuildDir "addon.d") -Recurse -Force
    }

    # Copy harvested components
    Copy-Item -Path (Join-Path $StagingDir "*") -Destination (Join-Path $RecBuildDir "system") -Recurse -Force

    # Copy harvested properties file to package root
    Copy-Item -Path $propOut -Destination (Join-Path $RecBuildDir "motocamera.prop") -Force

    # Ensure output directory exists
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    $AbsOutputDir = (Resolve-Path $OutputDir).Path
    $ZipOutputPath = Join-Path $AbsOutputDir ("MotoCameraRestored_" + $DeviceCodename + "_Recovery_Installer.zip")

    if (Test-Path $ZipOutputPath) {
        Remove-Item -Path $ZipOutputPath -Force
    }

    # Package Zip
    Log-Info "Packaging zip archive: $ZipOutputPath ..."
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $posix755 = -2115174400
    $posix644 = -2119958528

    $zipStream = [System.IO.File]::Open($ZipOutputPath, [System.IO.FileMode]::Create)
    $zipArchive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

    try {
        $buildFiles = Get-ChildItem -Path $RecBuildDir -Recurse -File
        $baseLen = $RecBuildDir.TrimEnd('\').Length + 1

        foreach ($file in $buildFiles) {
            $relPath = $file.FullName.Substring($baseLen).Replace('\', '/')
            $entry = $zipArchive.CreateEntry($relPath, [System.IO.Compression.CompressionLevel]::Optimal)

            $fs = [System.IO.File]::OpenRead($file.FullName)
            $es = $entry.Open()
            $fs.CopyTo($es)
            $es.Dispose()
            $fs.Dispose()

            if ($relPath -eq "META-INF/com/google/android/update-binary" -or `
                $relPath -eq "toybox" -or `
                $relPath -like "system/vendor/bin/hw/*" -or `
                $relPath -like "system/addon.d/*") {
                $entry.ExternalAttributes = $posix755
            } else {
                $entry.ExternalAttributes = $posix644
            }
        }
    } finally {
        $zipArchive.Dispose()
        $zipStream.Dispose()
    }

    # Write info text summary
    $infoPath = Join-Path $AbsOutputDir ("MotoCameraRestored_" + $DeviceCodename + "_info.txt")
    $infoContent = @(
        "================================================================================",
        "Moto Camera Restored -- Recovery Package Build Manifest",
        "================================================================================",
        "Device Model:       $DeviceModel",
        "Device Codename:    $DeviceCodename",
        "Hardware Platform:  $PlatformSoc",
        "Android Version:    $AndroidVersion (API SDK $SdkLevel)",
        "Stock Build ID:     $BuildId",
        "Camera Generation:  $CameraGenName ($CameraVer)",
        "Template Module:    $CameraGen",
        "Installer ZIP:      $([System.IO.Path]::GetFileName($ZipOutputPath))",
        "Build Timestamp:    $([System.DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss UTC'))",
        "================================================================================"
    ) -join [System.Environment]::NewLine
    Set-Content -Path $infoPath -Value $infoContent -Encoding ASCII

    $zipSizeMb = [math]::Round((Get-Item $ZipOutputPath).Length / 1MB, 2)
    Log-Ok "Recovery Installer created: $ZipOutputPath ($zipSizeMb MB)"
    Log-Ok "Build manifest saved: $infoPath"

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "          Universal Recovery Package Compiled Successfully!                     " -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Target Device:" -ForegroundColor White
    Write-Host "  --> Model:      $DeviceModel" -ForegroundColor Cyan
    Write-Host "  --> Codename:   $DeviceCodename" -ForegroundColor Cyan
    Write-Host "  --> Generation: $CameraGenName ($CameraVer)" -ForegroundColor Cyan
    Write-Host "  --> Module:     templates/$CameraGen" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installer Package:" -ForegroundColor White
    Write-Host "  --> $ZipOutputPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "How to install via Lineage Recovery / TWRP / OrangeFox:" -ForegroundColor White
    Write-Host "  1. Reboot your phone into Recovery mode."
    Write-Host "  2. Select 'Apply Update' -> 'Apply from ADB' (or 'Install' in TWRP/OrangeFox)."
    Write-Host "  3. From your PC terminal / Command Prompt, run:"
    Write-Host "       adb sideload `"$ZipOutputPath`"" -ForegroundColor Yellow
    Write-Host "  4. If prompted with 'Signature verification failed. Install anyway?', select 'Yes'."
    Write-Host "  5. Reboot system. Native $CameraGenName is restored and ready to use!"
    Write-Host ""
    Write-Host "[OTA Survival] The included addon.d script will automatically" -ForegroundColor Cyan
    Write-Host "preserve the camera suite across nightly custom ROM updates."
    Write-Host ""

} finally {
    if (Test-Path $TempWorkDir) {
        Remove-Item -Path $TempWorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
