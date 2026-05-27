#Requires -Version 5.1
<#
.SYNOPSIS
    ComicDiet Setup - One-time installer and dependency bootstrapper.
.DESCRIPTION
    Run this once after cloning or downloading ComicDiet.
    Handles everything required to run ComicDiet:

      1. Detects PowerShell version and relaunches in PS7 if available,
         or installs PS7 via winget if not.
      2. Sets the execution policy for the current user (RemoteSigned).
      3. Unblocks all .ps1 files in the scripts/ folder (required after ZIP download).
      4. Installs 7-Zip via winget if not already present.
      5. Downloads cjpegli.exe from the official libjxl GitHub release,
         extracts it into scripts/, and displays its SHA-256 hash.
      6. Optionally registers a right-click context menu entry on folders
         (launches the GUI with the folder pre-populated).
      7. Optionally creates a Desktop shortcut to ComicDiet.bat.

    Safe to re-run. All steps are idempotent.
#>

# -------------------------------------------------------------------------
# Catppuccin Mocha palette (matches ComicDiet.ps1 and ComicDiet-CLI.ps1)
# -------------------------------------------------------------------------
$ESC = [char]27
$CtpText      = "$ESC[38;2;205;214;244m" # CDD6F4 - primary text
$CtpSubtext0  = "$ESC[38;2;166;173;200m" # A6ADC8 - muted text
$CtpOverlay0  = "$ESC[38;2;108;112;134m" # 6C7086 - decorative
$CtpMauve     = "$ESC[38;2;203;166;247m" # CBA6F7 - primary accent (brand)
$CtpLavender  = "$ESC[38;2;180;190;254m" # B4BEFE - secondary accent
$CtpSky       = "$ESC[38;2;137;220;235m" # 89DCEB - headers
$CtpGreen     = "$ESC[38;2;166;227;161m" # A6E3A1 - success
$CtpYellow    = "$ESC[38;2;249;226;175m" # F9E2AF - warnings
$CtpRed       = "$ESC[38;2;243;139;168m" # F38BA8 - errors
$Reset        = "$ESC[0m"
$Border       = "=" * 47

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------
function Write-Header {
    Write-Host ""
    Write-Host "${CtpMauve}$Border${Reset}"
    Write-Host "${CtpSky}          COMICDIET SETUP INSTALLER          ${Reset}"
    Write-Host "${CtpMauve}$Border${Reset}"
    Write-Host "${CtpOverlay0}   Installing dependencies for ComicDiet.ps1  ${Reset}"
    Write-Host "${CtpMauve}$Border${Reset}"
    Write-Host ""
}

function Write-StepOK($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpGreen}[ OK ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpGreen}[ OK ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-StepWarn($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpYellow}[ !! ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpYellow}[ !! ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-StepFail($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpRed}[ XX ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpRed}[ XX ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-StepInfo($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpLavender}[ >> ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpLavender}[ >> ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-Indent($text) {
    Write-Host "        ${CtpOverlay0}$text${Reset}"
}

# -------------------------------------------------------------------------
# Step 0: PowerShell Version Check and Relaunch
# -------------------------------------------------------------------------
# setup.ps1 requires only PS 5.1 so Install.bat can launch it via the
# built-in powershell.exe. If PS7 is already installed, we silently
# relaunch in it (required for Step 4/5 which use PS7 features).
# If PS7 is missing entirely, we install it and prompt the user to retry.

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue

    if ($pwsh) {
        # PS7 found - silently relaunch this script in it and exit PS5.
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $scriptPath @args
        exit $LASTEXITCODE
    }

    # PS7 not installed yet. Show header and handle.
    Write-Header

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-StepFail "winget not available"
        Write-Indent "Install 'App Installer' from the Microsoft Store, then re-run."
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-StepInfo "PowerShell 7 not found" "Installing via winget..."
    Write-Host ""

    try {
        winget install `
            --id Microsoft.PowerShell `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements
    } catch {
        Write-StepFail "PowerShell 7 installation failed" "$_"
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Host ""
    Write-StepOK "PowerShell 7 installed"
    Write-Host ""
    Write-Host "${CtpYellow} Action required:${Reset} Close this window and double-click ${CtpText}Install.bat${Reset} again."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

# -------------------------------------------------------------------------
# Running in PS7+. Proceed with full setup.
# -------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$ScriptDir    = $PSScriptRoot                                      # scripts/
$RepoRoot     = Split-Path $ScriptDir -Parent                      # repo root
$MainScript   = Join-Path $ScriptDir "ComicDiet.ps1"               # GUI (primary)
$CliScript    = Join-Path $ScriptDir "ComicDiet-CLI.ps1"           # engine (secondary)
$CjpegliPath  = Join-Path $ScriptDir "cjpegli.exe"                 # downloaded by this script
$LauncherBat  = Join-Path $RepoRoot  "ComicDiet.bat"               # user-facing launcher
$7zPath       = "C:\Program Files\7-Zip\7z.exe"

Write-Header

# -------------------------------------------------------------------------
# Step 1: Execution Policy
# -------------------------------------------------------------------------
Write-StepInfo "Execution policy..."
try {
    $current = Get-ExecutionPolicy -Scope CurrentUser
    if ($current -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Write-StepOK "Execution policy" "Already set to $current (CurrentUser)"
    } else {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-StepOK "Execution policy" "Set to RemoteSigned (CurrentUser)"
    }
} catch {
    Write-StepWarn "Execution policy" "Could not set automatically - run manually if needed:"
    Write-Indent "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

# -------------------------------------------------------------------------
# Step 2: Unblock script files
# Unblocks the Zone.Identifier ADS added when files are downloaded via browser.
# Git clone skips this; ZIP download does not.
# -------------------------------------------------------------------------
Write-StepInfo "Unblocking script files..."
$unblocked = 0
Get-ChildItem -Path $ScriptDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -Path $_.FullName -ErrorAction Stop; $unblocked++ } catch {}
}
if ($unblocked -gt 0) {
    Write-StepOK "Script files unblocked" "$unblocked file(s)"
} else {
    Write-StepOK "Script files" "No unblocking needed (likely a git clone)"
}

# -------------------------------------------------------------------------
# Step 3: winget availability
# -------------------------------------------------------------------------
Write-StepInfo "Checking winget..."
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-StepFail "winget not found"
    Write-Indent "Install 'App Installer' from the Microsoft Store, then re-run."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
$wingetVer = (winget --version 2>$null)
Write-StepOK "winget" "$wingetVer"

# -------------------------------------------------------------------------
# Step 4: 7-Zip
# -------------------------------------------------------------------------
Write-StepInfo "Checking 7-Zip..."
if (Test-Path $7zPath) {
    Write-StepOK "7-Zip" "Found at $7zPath"
} else {
    Write-StepInfo "7-Zip not found" "Installing via winget..."
    try {
        winget install `
            --id 7zip.7zip `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements

        if (Test-Path $7zPath) {
            Write-StepOK "7-Zip installed" $7zPath
        } else {
            # winget may need a PATH refresh before the exe is visible
            Write-StepWarn "7-Zip installed but path not verified yet" "May require a shell restart"
        }
    } catch {
        Write-StepFail "7-Zip installation failed" "$_"
        Write-Indent "Download manually from https://7-zip.org and install to the default path."
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# -------------------------------------------------------------------------
# Step 5: cjpegli.exe
# Downloads from the official libjxl GitHub release. Extracts cjpegli.exe
# into the same folder as ComicDiet.ps1. Displays SHA-256 for verification.
# -------------------------------------------------------------------------
Write-StepInfo "Checking cjpegli.exe..."

if (Test-Path $CjpegliPath) {
    $existingHash = (Get-FileHash $CjpegliPath -Algorithm SHA256).Hash
    Write-StepOK "cjpegli.exe" "Already present"
    Write-Indent "SHA-256: $existingHash"
    Write-Indent "To upgrade, delete cjpegli.exe and re-run setup."
} else {
    Write-StepInfo "Fetching latest libjxl release from GitHub..."

    try {
        $apiUrl  = "https://api.github.com/repos/libjxl/libjxl/releases/latest"
        $headers = @{
            "User-Agent" = "ComicDiet-Setup/1.0"
            "Accept"     = "application/vnd.github+json"
        }

        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers
        $version = $release.tag_name

        # Find the Windows x64 zip. Typical name: jxl-x64-windows-static.zip
        $asset = $release.assets | Where-Object {
            $_.name -match "windows" -and
            $_.name -match "x64"     -and
            $_.name -match "\.zip$"
        } | Select-Object -First 1

        if (-not $asset) {
            Write-StepFail "No Windows x64 zip found in libjxl $version release"
            Write-Indent "Download cjpegli.exe manually from:"
            Write-Indent "https://github.com/libjxl/libjxl/releases/latest"
            Write-Indent "Place it in: $ScriptDir"
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }

        $sizeMB = [math]::Round($asset.size / 1MB, 1)
        Write-StepOK "libjxl release" "$version - $($asset.name) ($sizeMB MB)"
        Write-StepInfo "Downloading..."

        $TempDir = Join-Path $env:TEMP "ComicDiet_Setup_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
        $ZipPath = Join-Path $TempDir $asset.name

        try {
            Invoke-WebRequest `
                -Uri $asset.browser_download_url `
                -OutFile $ZipPath `
                -Headers $headers `
                -ProgressAction Continue

            Write-StepInfo "Extracting cjpegli.exe..."
            Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force

            $found = Get-ChildItem -Path $TempDir -Filter "cjpegli.exe" -Recurse -File |
                     Select-Object -First 1

            if (-not $found) {
                Write-StepFail "cjpegli.exe not found inside $($asset.name)"
                Write-Indent "The release asset structure may have changed."
                Write-Indent "Please report this at: https://github.com/YOUR_USERNAME/ComicDiet/issues"
                exit 1
            }

            Copy-Item -Path $found.FullName -Destination $CjpegliPath -Force

            $hash = (Get-FileHash $CjpegliPath -Algorithm SHA256).Hash
            Write-StepOK "cjpegli.exe installed" $CjpegliPath
            Write-Indent "Version : $version"
            Write-Indent "SHA-256 : $hash"
            Write-Indent "Verify  : https://github.com/libjxl/libjxl/releases/tag/$version"

        } finally {
            Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

    } catch {
        Write-StepFail "Download failed" "$_"
        Write-Indent "Check your internet connection and try again."
        Write-Indent "Or download cjpegli.exe manually from:"
        Write-Indent "https://github.com/libjxl/libjxl/releases/latest"
        Write-Indent "and place it in: $ScriptDir"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# -------------------------------------------------------------------------
# Step 6: Right-click context menu (optional)
# Registers under HKCU - no admin required.
# -------------------------------------------------------------------------
Write-Host ""
$regKey  = "HKCU:\Software\Classes\Directory\shell\ComicDiet"
$already = Test-Path $regKey

if ($already) {
    Write-StepOK "Context menu" "Already registered ('Optimize with ComicDiet')"
    Write-Host "${CtpOverlay0}   To remove it, delete: $regKey${Reset}"
} else {
    Write-Host "${CtpText} Add 'Optimize with ComicDiet' to folder right-click menu?${Reset} ${CtpOverlay0}(y/N)${Reset} " -NoNewline
    $answer = $Host.UI.ReadLine()

    if ($answer -match "^[Yy]$") {
        try {
            # Icon: prefer custom ComicDiet.ico, fall back to imageres.dll
            $customIco = Join-Path $ScriptDir "ComicDiet.ico"
            $ctxIcon   = if (Test-Path $customIco) {
                "$customIco,0"
            } else {
                "$env:SystemRoot\System32\imageres.dll,13"
            }

            New-Item -Path $regKey -Force | Out-Null
            Set-ItemProperty -Path $regKey -Name "(default)" -Value "Optimize with ComicDiet"
            Set-ItemProperty -Path $regKey -Name "Icon"      -Value $ctxIcon

            New-Item -Path "$regKey\command" -Force | Out-Null
            Set-ItemProperty -Path "$regKey\command" -Name "(default)" `
                -Value "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$MainScript`" -Source `"%1`""

            Write-StepOK "Context menu registered" "Right-click any folder > Optimize with ComicDiet"
        } catch {
            Write-StepWarn "Context menu registration failed" "$_"
        }
    } else {
        Write-Host "${CtpOverlay0}   Skipped. You can re-run setup anytime to add it.${Reset}"
    }
}

# -------------------------------------------------------------------------
# Step 7: Desktop shortcut (optional)
# Creates a .lnk on the Desktop pointing to ComicDiet.bat.
# Uses ComicDiet.ico if present, falls back to imageres.dll (system icon).
# -------------------------------------------------------------------------
Write-Host ""
Write-Host "${CtpText} Create a Desktop shortcut for ComicDiet?${Reset} ${CtpOverlay0}(y/N)${Reset} " -NoNewline
$shortcutAnswer = $Host.UI.ReadLine()

if ($shortcutAnswer -match "^[Yy]$") {
    try {
        $lnkPath = Join-Path ([System.Environment]::GetFolderPath("Desktop")) "ComicDiet.lnk"
        $WshShell = New-Object -ComObject WScript.Shell
        $lnk = $WshShell.CreateShortcut($lnkPath)
        $lnk.TargetPath       = $LauncherBat
        $lnk.WorkingDirectory = $RepoRoot
        $lnk.Description      = "ComicDiet - Comic Archive Optimizer"

        $customIco = Join-Path $ScriptDir "ComicDiet.ico"
        $lnk.IconLocation = if (Test-Path $customIco) {
            "$customIco,0"
        } else {
            "$env:SystemRoot\System32\imageres.dll,13"
        }

        $lnk.Save()
        Write-StepOK "Desktop shortcut created" $lnkPath
    } catch {
        Write-StepWarn "Shortcut creation failed" "$_"
    }
} else {
    Write-Host "${CtpOverlay0}   Skipped.${Reset}"
}

# -------------------------------------------------------------------------
# Step 8: Uninstall shortcut in repo root
# Always created - not optional. Gives Uninstall.bat a recycle bin icon
# in Explorer without modifying any system-wide file associations.
# Icon: shell32.dll index 31 = empty recycle bin (stable across Windows 10/11).
# -------------------------------------------------------------------------
$UninstallBat = Join-Path $ScriptDir "Uninstall.bat"
$UninstallLnk = Join-Path $RepoRoot "Uninstall.lnk"

if (Test-Path $UninstallBat) {
    try {
        $wsh2  = New-Object -ComObject WScript.Shell
        $ulnk  = $wsh2.CreateShortcut($UninstallLnk)
        $ulnk.TargetPath       = $UninstallBat
        $ulnk.WorkingDirectory = $RepoRoot
        $ulnk.Description      = "Uninstall ComicDiet"
        $ulnk.IconLocation     = "$env:SystemRoot\System32\shell32.dll,31"
        $ulnk.Save()
        Write-StepOK "Uninstall shortcut created" $UninstallLnk
    } catch {
        Write-StepWarn "Uninstall shortcut" "Could not create: $_"
    }
} else {
    Write-StepWarn "Uninstall shortcut" "Uninstall.bat not found at repo root - skipping"
}

# -------------------------------------------------------------------------
# Final Summary
# -------------------------------------------------------------------------
Write-Host ""
Write-Host "${CtpMauve}$Border${Reset}"
Write-Host "${CtpGreen}             SETUP COMPLETE                   ${Reset}"
Write-Host "${CtpMauve}$Border${Reset}"
Write-Host ""
Write-Host "${CtpText} ComicDiet is ready.${Reset}"
Write-Host ""
Write-Host "${CtpOverlay0}   Double-click ComicDiet.bat to open the app.${Reset}"
if (Test-Path $regKey) {
    Write-Host "${CtpOverlay0}   Or right-click any folder > Optimize with ComicDiet${Reset}"
}
Write-Host ""
Write-Host "${CtpText} CLI (advanced):${Reset}"
Write-Host "${CtpOverlay0}   pwsh -File `"$CliScript`" -Source `"C:\Path\To\Comics`"${Reset}"
Write-Host ""
Write-Host "${CtpText} CLI flags:${Reset}"
Write-Host "${CtpOverlay0}   -DryRun        Preview without modifying files${Reset}"
Write-Host "${CtpOverlay0}   -KeepOriginals Skip moving originals to Recycle Bin${Reset}"
Write-Host ""
Write-Host "${CtpMauve}$Border${Reset}"
Write-Host ""

Read-Host "Press Enter to exit"
