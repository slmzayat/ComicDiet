#Requires -Version 5.1
<#
.SYNOPSIS
    ComicDiet Setup - One-time installer and dependency bootstrapper.
.DESCRIPTION
    Run this once after cloning or downloading ComicDiet.
    Handles everything required to run ComicDiet.ps1:

      1. Detects PowerShell version and relaunches in PS7 if available,
         or installs PS7 via winget if not.
      2. Sets the execution policy for the current user (RemoteSigned).
      3. Unblocks all .ps1 files in the repo (required after ZIP download).
      4. Installs 7-Zip via winget if not already present.
      5. Downloads cjpegli.exe from the official libjxl GitHub release,
         extracts it into this folder, and displays its SHA-256 hash.
      6. Optionally registers a right-click context menu entry on folders.

    Safe to re-run. All steps are idempotent.
#>

# -------------------------------------------------------------------------
# Dracula Theme (matches ComicDiet.ps1)
# -------------------------------------------------------------------------
$ESC    = [char]27
$DrFg      = "$ESC[38;2;248;248;242m" # F8F8F2 Foreground
$DrCyan    = "$ESC[38;2;139;233;253m" # 8BE9FD Cyan
$DrGreen   = "$ESC[38;2;80;250;123m"  # 50FA7B Green
$DrYellow  = "$ESC[38;2;241;250;140m" # F1FA8C Yellow
$DrPink    = "$ESC[38;2;255;121;198m" # FF79C6 Pink
$DrPurple  = "$ESC[38;2;189;147;249m" # BD93F9 Purple
$DrRed     = "$ESC[38;2;255;85;85m"   # FF5555 Red
$DrDim     = "$ESC[38;2;98;114;164m"  # 6272A4 Comment
$Reset     = "$ESC[0m"
$Border    = "=" * 47

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------
function Write-Header {
    Write-Host ""
    Write-Host "${DrPink}$Border${Reset}"
    Write-Host "${DrCyan}          COMICDIET SETUP INSTALLER          ${Reset}"
    Write-Host "${DrPink}$Border${Reset}"
    Write-Host "${DrDim}   Installing dependencies for ComicDiet.ps1  ${Reset}"
    Write-Host "${DrPink}$Border${Reset}"
    Write-Host ""
}

function Write-StepOK($label, $detail = "") {
    if ($detail) {
        Write-Host "${DrGreen}[ OK ]${Reset} ${DrFg}$label${Reset} ${DrDim}$detail${Reset}"
    } else {
        Write-Host "${DrGreen}[ OK ]${Reset} ${DrFg}$label${Reset}"
    }
}

function Write-StepWarn($label, $detail = "") {
    if ($detail) {
        Write-Host "${DrYellow}[ !! ]${Reset} ${DrFg}$label${Reset} ${DrDim}$detail${Reset}"
    } else {
        Write-Host "${DrYellow}[ !! ]${Reset} ${DrFg}$label${Reset}"
    }
}

function Write-StepFail($label, $detail = "") {
    if ($detail) {
        Write-Host "${DrRed}[ XX ]${Reset} ${DrFg}$label${Reset} ${DrDim}$detail${Reset}"
    } else {
        Write-Host "${DrRed}[ XX ]${Reset} ${DrFg}$label${Reset}"
    }
}

function Write-StepInfo($label, $detail = "") {
    if ($detail) {
        Write-Host "${DrPurple}[ >> ]${Reset} ${DrFg}$label${Reset} ${DrDim}$detail${Reset}"
    } else {
        Write-Host "${DrPurple}[ >> ]${Reset} ${DrFg}$label${Reset}"
    }
}

function Write-Indent($text) {
    Write-Host "        ${DrDim}$text${Reset}"
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
    Write-Host "${DrYellow} Action required:${Reset} Close this window and double-click ${DrFg}Install.bat${Reset} again."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

# -------------------------------------------------------------------------
# Running in PS7+. Proceed with full setup.
# -------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$ScriptDir   = $PSScriptRoot
$MainScript  = Join-Path $ScriptDir "ComicDiet.ps1"
$CjpegliPath = Join-Path $ScriptDir "cjpegli.exe"
$7zPath      = "C:\Program Files\7-Zip\7z.exe"

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
                Write-Indent "Please report this at: https://github.com/slmzayat/ComicDiet/issues"
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
    Write-Host "${DrDim}   To remove it, delete: $regKey${Reset}"
} else {
    Write-Host "${DrFg} Add 'Optimize with ComicDiet' to folder right-click menu?${Reset} ${DrDim}(y/N)${Reset} " -NoNewline
    $answer = $Host.UI.ReadLine()

    if ($answer -match "^[Yy]$") {
        try {
            New-Item -Path $regKey -Force | Out-Null
            Set-ItemProperty -Path $regKey -Name "(default)"    -Value "Optimize with ComicDiet"
            Set-ItemProperty -Path $regKey -Name "Icon"         -Value "`"$CjpegliPath`",0"

            New-Item -Path "$regKey\command" -Force | Out-Null
            Set-ItemProperty -Path "$regKey\command" -Name "(default)" `
                -Value "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$MainScript`" -Target `"%1`""

            Write-StepOK "Context menu registered" "Right-click any folder > Optimize with ComicDiet"
        } catch {
            Write-StepWarn "Context menu registration failed" "$_"
        }
    } else {
        Write-Host "${DrDim}   Skipped. You can re-run setup anytime to add it.${Reset}"
    }
}

# -------------------------------------------------------------------------
# Final Summary
# -------------------------------------------------------------------------
Write-Host ""
Write-Host "${DrPink}$Border${Reset}"
Write-Host "${DrGreen}             SETUP COMPLETE                   ${Reset}"
Write-Host "${DrPink}$Border${Reset}"
Write-Host ""
Write-Host "${DrFg} ComicDiet is ready. Run it with:${Reset}"
Write-Host ""
Write-Host "${DrDim}   pwsh -File `"$MainScript`" -Target `"C:\Path\To\Comics`"${Reset}"
Write-Host ""
if (Test-Path $regKey) {
    Write-Host "${DrDim}   Or right-click any folder > Optimize with ComicDiet${Reset}"
    Write-Host ""
}
Write-Host "${DrFg} Flags:${Reset}"
Write-Host "${DrDim}   -DryRun        Preview changes without processing${Reset}"
Write-Host "${DrDim}   -KeepOriginals Skip moving originals to Recycle Bin${Reset}"
Write-Host ""
Write-Host "${DrPink}$Border${Reset}"
Write-Host ""

Read-Host "Press Enter to exit"
