#Requires -Version 5.1
<#
.SYNOPSIS
    ComicDiet Uninstaller - Removes all ComicDiet components from this system.
.DESCRIPTION
    Removes, in order:
      1. Right-click context menu entry (HKCU registry)
      2. Desktop shortcut (ComicDiet.lnk)
      3. Downloaded binary (scripts/cjpegli.exe) -> Recycle Bin
      4. Runtime directory (scripts/Temp/)       -> Recycle Bin
      5. Entire ComicDiet folder                 -> Recycle Bin (optional, confirms twice)

    Does NOT remove:
      - 7-Zip  (system-wide install, may be used by other tools)
      - PowerShell 7  (system-wide, definitely keep)
      - Execution policy  (per-user setting; reverting blindly could break other scripts)

    Safe to re-run. Every step checks state before acting.
#>

# ─────────────────────────────────────────────────────────────────────────────
# Catppuccin Mocha palette
# Destructive script: Red replaces Mauve as primary accent to signal danger.
# ─────────────────────────────────────────────────────────────────────────────
$ESC         = [char]27
$CtpText     = "$ESC[38;2;205;214;244m" # CDD6F4 - primary text
$CtpSubtext0 = "$ESC[38;2;166;173;200m" # A6ADC8 - muted text
$CtpOverlay0 = "$ESC[38;2;108;112;134m" # 6C7086 - decorative
$CtpRed      = "$ESC[38;2;243;139;168m" # F38BA8 - primary accent (destructive)
$CtpGreen    = "$ESC[38;2;166;227;161m" # A6E3A1 - success / skipped (nothing to do)
$CtpYellow   = "$ESC[38;2;249;226;175m" # F9E2AF - warnings / prompts
$CtpPeach    = "$ESC[38;2;250;179;135m" # FAB387 - partial / already gone
$Reset       = "$ESC[0m"
$Border      = "=" * 47

# ─────────────────────────────────────────────────────────────────────────────
# Paths  (mirrors setup.ps1 conventions)
# ─────────────────────────────────────────────────────────────────────────────
$ScriptDir   = $PSScriptRoot                          # scripts/
$RepoRoot    = Split-Path $ScriptDir -Parent          # repo root
$RegKey      = "HKCU:\Software\Classes\Directory\shell\ComicDiet"
$DesktopLnk  = Join-Path ([System.Environment]::GetFolderPath("Desktop")) "ComicDiet.lnk"
$CjpegliPath = Join-Path $ScriptDir "cjpegli.exe"
$TempDir     = Join-Path $ScriptDir "Temp"

Add-Type -AssemblyName Microsoft.VisualBasic

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    Write-Host ""
    Write-Host "${CtpRed}$Border${Reset}"
    Write-Host "${CtpRed}           COMICDIET UNINSTALLER              ${Reset}"
    Write-Host "${CtpRed}$Border${Reset}"
    Write-Host "${CtpSubtext0}   This will remove ComicDiet from your system.  ${Reset}"
    Write-Host "${CtpRed}$Border${Reset}"
    Write-Host ""
}

function Write-Done($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpGreen}[ OK ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpGreen}[ OK ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-Skip($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpPeach}[ -- ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpPeach}[ -- ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-Fail($label, $detail = "") {
    if ($detail) {
        Write-Host "${CtpRed}[ XX ]${Reset} ${CtpText}$label${Reset} ${CtpOverlay0}$detail${Reset}"
    } else {
        Write-Host "${CtpRed}[ XX ]${Reset} ${CtpText}$label${Reset}"
    }
}

function Write-Indent($text) {
    Write-Host "        ${CtpOverlay0}$text${Reset}"
}

function Confirm-Step($prompt) {
    Write-Host "${CtpYellow}[ ?? ]${Reset} ${CtpText}$prompt${Reset} ${CtpOverlay0}(y/N)${Reset} " -NoNewline
    $answer = $Host.UI.ReadLine()
    return ($answer -match "^[Yy]$")
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner

Write-Host "${CtpYellow} The following will be removed:${Reset}"
Write-Host "${CtpOverlay0}   - Right-click context menu entry${Reset}"
Write-Host "${CtpOverlay0}   - Desktop shortcut (ComicDiet.lnk)${Reset}"
Write-Host "${CtpOverlay0}   - scripts\cjpegli.exe (moved to Recycle Bin)${Reset}"
Write-Host "${CtpOverlay0}   - scripts\Temp\ (moved to Recycle Bin)${Reset}"
Write-Host "${CtpOverlay0}   - Optionally: the entire ComicDiet folder${Reset}"
Write-Host ""

if (-not (Confirm-Step "Continue with uninstall?")) {
    Write-Host ""
    Write-Host "${CtpSubtext0} Uninstall cancelled. Nothing was changed.${Reset}"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Host ""
$RemovedCount = 0
$SkippedCount = 0
$FailedCount  = 0

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Context menu entry
# ─────────────────────────────────────────────────────────────────────────────
if (Test-Path $RegKey) {
    try {
        Remove-Item -Path $RegKey -Recurse -Force
        Write-Done "Context menu entry removed"
        $RemovedCount++
    } catch {
        Write-Fail "Context menu entry" "Could not remove: $_"
        Write-Indent "Delete manually: $RegKey"
        $FailedCount++
    }
} else {
    Write-Skip "Context menu entry" "Not registered"
    $SkippedCount++
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Desktop shortcut
# ─────────────────────────────────────────────────────────────────────────────
if (Test-Path $DesktopLnk) {
    try {
        Remove-Item -Path $DesktopLnk -Force
        Write-Done "Desktop shortcut removed" $DesktopLnk
        $RemovedCount++
    } catch {
        Write-Fail "Desktop shortcut" "Could not remove: $_"
        $FailedCount++
    }
} else {
    Write-Skip "Desktop shortcut" "Not found"
    $SkippedCount++
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: cjpegli.exe -> Recycle Bin
# ─────────────────────────────────────────────────────────────────────────────
if (Test-Path $CjpegliPath) {
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $CjpegliPath,
            'OnlyErrorDialogs',
            'SendToRecycleBin'
        )
        Write-Done "cjpegli.exe recycled" $CjpegliPath
        $RemovedCount++
    } catch {
        Write-Fail "cjpegli.exe" "Could not recycle: $_"
        Write-Indent "Delete manually: $CjpegliPath"
        $FailedCount++
    }
} else {
    Write-Skip "cjpegli.exe" "Not found"
    $SkippedCount++
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: scripts/Temp/ -> Recycle Bin
# ─────────────────────────────────────────────────────────────────────────────
if (Test-Path $TempDir) {
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $TempDir,
            'OnlyErrorDialogs',
            'SendToRecycleBin'
        )
        Write-Done "Temp directory recycled" $TempDir
        $RemovedCount++
    } catch {
        Write-Fail "Temp directory" "Could not recycle: $_"
        Write-Indent "Delete manually: $TempDir"
        $FailedCount++
    }
} else {
    Write-Skip "Temp directory" "Not found"
    $SkippedCount++
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Entire ComicDiet folder -> Recycle Bin (double-confirmed)
# Self-deletion: PowerShell has already loaded this script into memory.
# Sending the parent directory to the Recycle Bin works reliably on Windows.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "${CtpRed}$Border${Reset}"
Write-Host "${CtpRed} OPTIONAL: Remove the entire ComicDiet folder?  ${Reset}"
Write-Host "${CtpRed}$Border${Reset}"
Write-Host "${CtpOverlay0} Folder: $RepoRoot${Reset}"
Write-Host ""

if (Confirm-Step "Send ComicDiet folder to Recycle Bin?") {
    Write-Host ""
    # Second confirmation - this is a destructive irreversible-ish action
    Write-Host "${CtpRed} This will delete all scripts, config, and the icon.${Reset}"
    if (Confirm-Step "Are you sure?") {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $RepoRoot,
                'OnlyErrorDialogs',
                'SendToRecycleBin'
            )
            # If we get here the folder was successfully recycled.
            # The script continues in memory.
            Write-Host ""
            Write-Done "ComicDiet folder recycled" $RepoRoot
            $RemovedCount++
        } catch {
            Write-Fail "ComicDiet folder" "Could not recycle: $_"
            Write-Indent "Delete manually: $RepoRoot"
            $FailedCount++
        }
    } else {
        Write-Skip "ComicDiet folder" "Kept (second confirmation declined)"
        $SkippedCount++
    }
} else {
    Write-Skip "ComicDiet folder" "Kept"
    $SkippedCount++
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "${CtpRed}$Border${Reset}"
Write-Host "${CtpText}           UNINSTALL SUMMARY                  ${Reset}"
Write-Host "${CtpRed}$Border${Reset}"
Write-Host "${CtpGreen} Removed : $RemovedCount item(s)${Reset}"
if ($SkippedCount -gt 0) {
    Write-Host "${CtpPeach} Skipped : $SkippedCount item(s) (already absent or kept)${Reset}"
}
if ($FailedCount -gt 0) {
    Write-Host "${CtpRed} Failed  : $FailedCount item(s)  (see messages above)${Reset}"
}
Write-Host "${CtpRed}$Border${Reset}"
Write-Host ""

if ($FailedCount -eq 0) {
    Write-Host "${CtpSubtext0} ComicDiet has been removed. Thanks for using it.${Reset}"
} else {
    Write-Host "${CtpYellow} Uninstall completed with errors. Check the items above.${Reset}"
}

Write-Host ""
Read-Host "Press Enter to exit"
