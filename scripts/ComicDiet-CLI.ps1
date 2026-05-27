#Requires -Version 7.4
<#
.SYNOPSIS
    ComicDiet CLI - Comic Archive Optimization Engine
.DESCRIPTION
    The CLI engine for ComicDiet. Can be run directly for scripting and
    automation, or launched by ComicDiet.ps1 (the GUI).

    Extracts, sanitizes, optimizes, and repacks comic archives sequentially.
    JPEG images are re-encoded using Google Jpegli (-d 1.0, chroma 4:4:4).
    WebP images are preserved as-is. Output is always .cbz format.
    Image processing is parallelized at BelowNormal priority.
#>

[CmdletBinding(DefaultParameterSetName='Direct')]
param(
    [Parameter(ParameterSetName='Direct', Mandatory=$true, Position=0)]
    [string[]]$Source,

    # Alternative: read paths from a UTF-8 text file (one per line).
    # Used by the GUI to safely handle paths containing commas, quotes, etc.
    [Parameter(ParameterSetName='ListFile', Mandatory=$true)]
    [string]$SourceListFile,

    [string]$PathTo7z = "C:\Program Files\7-Zip\7z.exe",
    [string]$PathToCjpegli = (Join-Path $PSScriptRoot "cjpegli.exe"),

    [switch]$DryRun,
    [switch]$KeepOriginals
)

# Resolve SourceListFile into $Source if provided
if ($PSCmdlet.ParameterSetName -eq 'ListFile') {
    if (-not (Test-Path $SourceListFile)) {
        throw "Source list file not found: $SourceListFile"
    }
    $Source = @(Get-Content -Path $SourceListFile -Encoding utf8 |
                ForEach-Object { $_.Trim() } |
                Where-Object   { $_ })
    if ($Source.Count -eq 0) { throw "Source list file is empty: $SourceListFile" }
}

# --- UI & UX: Catppuccin Mocha Palette (VT Escape Sequences) ---
# Strict adherence to the Catppuccin style guide:
# https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md
# Variable names match the official Catppuccin Mocha color names.
$PSStyle.Progress.View = 'Minimal'
$ESC = [char]27
$CtpText      = "$ESC[38;2;205;214;244m" # CDD6F4 - primary text
$CtpSubtext0  = "$ESC[38;2;166;173;200m" # A6ADC8 - muted text (WCAG AA on all surfaces)
$CtpOverlay0  = "$ESC[38;2;108;112;134m" # 6C7086 - decorative only (paths, borders)
$CtpMauve     = "$ESC[38;2;203;166;247m" # CBA6F7 - primary accent (brand)
$CtpLavender  = "$ESC[38;2;180;190;254m" # B4BEFE - secondary accent (repack phase)
$CtpSky       = "$ESC[38;2;137;220;235m" # 89DCEB - headers, optimize phase
$CtpGreen     = "$ESC[38;2;166;227;161m" # A6E3A1 - success
$CtpYellow    = "$ESC[38;2;249;226;175m" # F9E2AF - warnings
$CtpPeach     = "$ESC[38;2;250;179;135m" # FAB387 - extract phase
$CtpRed       = "$ESC[38;2;243;139;168m" # F38BA8 - errors / failures
$CtpTeal      = "$ESC[38;2;148;226;213m" # 94E2D5 - informational (WebP notice)
$Reset        = "$ESC[0m"

# Stage glyphs (ASCII keyboard-equivalents for terminal-safe rendering everywhere)
$IcoExtract  = ">>"
$IcoSanitize = "::"
$IcoOptimize = "**"
$IcoRepack   = "##"
$IcoSuccess  = "OK"
$IcoFailed   = "XX"
$IcoTrash    = "~~"
$IcoInfo     = ">>"
$IcoWebP     = "~~"

$ErrorActionPreference = "Stop"
$SupportedExtensions = @(".cbr", ".cbz", ".cb7", ".cbt")
$ImageExtensions = @(".jpg", ".jpeg", ".png")

# Required for SendToRecycleBin via Microsoft.VisualBasic.FileIO.FileSystem
Add-Type -AssemblyName Microsoft.VisualBasic

# --- Validation & Initialization ---
if (-not $DryRun) {
    if (-not (Test-Path $PathTo7z)) { throw "FATAL: 7-Zip not found at $PathTo7z" }
    if (-not (Test-Path $PathToCjpegli)) { throw "FATAL: cjpegli not found at $PathToCjpegli" }
}

# Source Parsing
# $Source is [string[]] - accepts one or more folders and/or individual archive files.
# OutputDir is anchored to the first valid input (consistent, predictable).
$Archives  = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$OutputDir = $null

foreach ($entry in $Source) {
    if (Test-Path $entry -PathType Container) {
        if (-not $OutputDir) { $OutputDir = Join-Path $entry "Optimized Comics" }
        $escaped = [regex]::Escape((Join-Path $entry "Optimized Comics"))
        Get-ChildItem -Path $entry -Recurse -File |
            Where-Object { ($SupportedExtensions -contains $_.Extension.ToLower()) -and ($_.FullName -notmatch $escaped) } |
            ForEach-Object { $Archives.Add($_) }
    } elseif (Test-Path $entry -PathType Leaf) {
        $file = Get-Item $entry
        if ($SupportedExtensions -contains $file.Extension.ToLower()) {
            $Archives.Add($file)
            if (-not $OutputDir) { $OutputDir = Join-Path $file.DirectoryName "Optimized Comics" }
        } else {
            Write-Host "${CtpYellow}[!] Skipping unsupported file: $entry${Reset}"
        }
    } else {
        Write-Host "${CtpYellow}[!] Skipping invalid path: $entry${Reset}"
    }
}

if (-not $OutputDir) { throw "No valid source paths found." }

$TotalFiles = $Archives.Count
if ($TotalFiles -eq 0) { Write-Host "[!] No supported comic archives found." -ForegroundColor Yellow; exit }

# Filename Regex Dictionary (Matches standard enclosures: (), [], {}, <>)
$RegexGroups = "Empire Syndicate|Son of Ultron-Empire|Digital HC|Deathglobe-GetComics|The Last Kryptonian-DCP|Pyrate-DCP|Marika-Empire|Zone-Empire|digital-Empire|Megan-Empire|Onyx-Empire|Empire|Minutemen Syndicate|Minutemen-Zone|Minutemen-PhD|Minutemen-DarthScanner|Minutemen-TheKid|Minutemen|Novus-Z|Novus-G|Novus|GetComics|GodMagnus|DCP|Kileko|Thorn|Phaze|BiteMe|Fawkes|Oroboros|TLK|Walkabout-DCP|Mephisto|digital|webrip|c2c|fixed|scan|HR"
$RegexPattern = "(?i)\s*[\(\[\{\<]($RegexGroups)[\)\]\}\>]\s*"

# Helper: strip dictionary tokens AND collapse residual whitespace
function Get-CleanName($BaseName) {
    return (($BaseName -replace $RegexPattern, " ") -replace "\s+", " ").Trim(" -_")
}

# Helper: human-readable duration (Xs / Xm00s / Xh00m00s)
function Format-Duration([TimeSpan]$ts) {
    if ($ts.TotalHours -ge 1) {
        return "{0:0}h{1:00}m{2:00}s" -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
    } elseif ($ts.TotalMinutes -ge 1) {
        return "{0:0}m{1:00}s" -f [math]::Floor($ts.TotalMinutes), $ts.Seconds
    } else {
        return "{0:0}s" -f [math]::Round($ts.TotalSeconds)
    }
}

# Concurrency Math (scales to host hardware; no artificial ceiling)
$RAM_MB = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024
$RAM_Limit = [Math]::Floor($RAM_MB / 500)
$Core_Limit = [Math]::Floor($env:NUMBER_OF_PROCESSORS * 0.75)
$ThrottleLimit = [Math]::Min($RAM_Limit, $Core_Limit)
if ($ThrottleLimit -lt 1) { $ThrottleLimit = 1 }

# --- Dry Run Execution ---
if ($DryRun) {
    Write-Host "`n${CtpYellow}[*] DRY RUN ACTIVATED. Operations simulated.${Reset}`n"
    Write-Host "${CtpOverlay0}Calculated Concurrency Limit: $ThrottleLimit threads"
    Write-Host "Output Directory: $OutputDir${Reset}"
    if (-not $KeepOriginals) {
        Write-Host "${CtpYellow}[*] Originals would be moved to Recycle Bin upon successful conversion.${Reset}"
    } else {
        Write-Host "${CtpOverlay0}[*] Originals would be preserved (-KeepOriginals).${Reset}"
    }
    Write-Host ""
    foreach ($Archive in $Archives) {
        $CleanName = Get-CleanName $Archive.BaseName
        Write-Host "${CtpText}IN : $($Archive.FullName)${Reset}"
        Write-Host "${CtpSky}OUT: $OutputDir\$CleanName.cbz${Reset}`n"
    }
    exit
}

# --- Environment Setup ---
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$ErrorLogPath = Join-Path $OutputDir "ComicDiet_Errors.log"
$TotalOriginalBytes = 0
$TotalOptimizedBytes = 0
$Counter = 0
$SuccessCount = 0
$FailCount = 0
$TrashCount = 0
$TrashFailures = 0
$SuccessfulOriginals = New-Object System.Collections.Generic.List[string]
$FailedArchives = New-Object System.Collections.Generic.List[PSObject]
$ScriptStartTime = [datetime]::Now

# Hoisted loop invariants
$BaseTemp  = Join-Path $PSScriptRoot "Temp"
$JunkFiles = @("thumbs.db", "desktop.ini", ".ds_store", "ethumbs.db", "._*")

$TotalInputMB = [math]::Round((($Archives | Measure-Object Length -Sum).Sum / 1MB), 2)
$OriginalsBehavior = if ($KeepOriginals) { "Preserved (-KeepOriginals)" } else { "Move to Recycle Bin on success" }

# ASCII art logo (figlet 'standard' font). Single-quoted strings preserve backslashes
# and apostrophes are escaped via doubling. Width: ~46 chars.
$Logo = @(
    '  ____                _      ____  _      _   ',
    ' / ___|___  _ __ ___ (_) ___|  _ \(_) ___| |_ ',
    '| |   / _ \| ''_ ` _ \| |/ __| | | | |/ _ \ __|',
    '| |__| (_) | | | | | | | (__| |_| | |  __/ |_ ',
    ' \____\___/|_| |_| |_|_|\___|____/|_|\___|\__|'
)
# Gradient: Pink > Pink > Purple > Cyan > Cyan (vampire-to-dawn)
$LogoColors = @($CtpMauve, $CtpMauve, $CtpLavender, $CtpSky, $CtpSky)
$Border = ("=" * 47)

Write-Host ""
Write-Host "${CtpMauve}$Border${Reset}"
for ($i = 0; $i -lt $Logo.Count; $i++) {
    Write-Host "$($LogoColors[$i])$($Logo[$i])${Reset}"
}
Write-Host "${CtpOverlay0}       Comic Archive Optimization Suite       ${Reset}"
Write-Host "${CtpMauve}$Border${Reset}"
$SourceDisplay = if ($Source.Count -eq 1) { $Source[0] } else { "$($Source.Count) sources" }
Write-Host "${CtpText} Source      : ${CtpOverlay0}$SourceDisplay${Reset}"
Write-Host "${CtpText} Output      : ${CtpOverlay0}$OutputDir${Reset}"
Write-Host "${CtpText} Archives    : $TotalFiles files ${CtpOverlay0}($TotalInputMB MB)${Reset}"
Write-Host "${CtpText} Concurrency : $ThrottleLimit threads${Reset}"
Write-Host "${CtpText} Originals   : ${CtpYellow}$OriginalsBehavior${Reset}"
Write-Host "${CtpMauve}$Border${Reset}"
Write-Host ""

# Summary renderer (invoked from finally to guarantee display on any exit path)
function Write-ComicDietSummary {
    if ($script:TotalFiles -le 0) { return }

    $SavedBytes = $script:TotalOriginalBytes - $script:TotalOptimizedBytes
    $SavedMB    = [math]::Round($SavedBytes / 1MB, 2)
    $PctSaved   = if ($script:TotalOriginalBytes -gt 0) {
        [math]::Round(($SavedBytes / $script:TotalOriginalBytes) * 100, 1)
    } else { 0 }
    $TotalRuntime = Format-Duration ([datetime]::Now - $script:ScriptStartTime)

    # Ensure any lingering progress bars are dismissed before printing summary
    Write-Progress -Activity "ComicDiet Pipeline" -Completed -ErrorAction SilentlyContinue
    Write-Progress -Activity "Image Optimization" -Completed -Id 2 -ErrorAction SilentlyContinue

    # Failure recap (rendered above the main summary)
    if ($script:FailedArchives.Count -gt 0) {
        Write-Host "`n${CtpRed}===============================================${Reset}"
        Write-Host "${CtpRed}                FAILED ARCHIVES                ${Reset}"
        Write-Host "${CtpRed}===============================================${Reset}"
        foreach ($f in $script:FailedArchives) {
            Write-Host "${CtpRed} -${Reset} ${CtpText}$($f.Name)${Reset}"
            Write-Host "   ${CtpOverlay0}$($f.Reason)${Reset}"
        }
    }

    Write-Host "`n${CtpMauve}===============================================${Reset}"
    Write-Host "${CtpSky}             COMICDIET BATCH SUMMARY           ${Reset}"
    Write-Host "${CtpMauve}===============================================${Reset}"
    Write-Host "${CtpText} Files Queued    : $script:TotalFiles${Reset}"
    Write-Host "${CtpGreen} Succeeded       : $script:SuccessCount${Reset}"
    if ($script:FailCount -gt 0) {
        Write-Host "${CtpRed} Failed          : $script:FailCount${Reset}"
    } else {
        Write-Host "${CtpOverlay0} Failed          : 0${Reset}"
    }
    Write-Host "${CtpOverlay0} Original Size   : $([math]::Round($script:TotalOriginalBytes / 1MB, 2)) MB${Reset}"
    Write-Host "${CtpLavender} Optimized Size  : $([math]::Round($script:TotalOptimizedBytes / 1MB, 2)) MB${Reset}"

    if ($SavedBytes -gt 0) {
        Write-Host "${CtpGreen} Space Reclaimed : $SavedMB MB${Reset}"
        Write-Host "${CtpGreen} Total Reduction : $PctSaved %${Reset}"
    } else {
        Write-Host "${CtpYellow} Space Reclaimed : $SavedMB MB${Reset}"
        Write-Host "${CtpYellow} Total Reduction : $PctSaved %${Reset}"
    }

    if ($script:TrashCount -gt 0) {
        Write-Host "${CtpYellow} Originals Recycled: $script:TrashCount (Recycle Bin)${Reset}"
    }
    if ($script:TrashFailures -gt 0) {
        Write-Host "${CtpRed} Recycle Failures : $script:TrashFailures${Reset}"
    }

    Write-Host "${CtpText} Total Runtime   : $TotalRuntime${Reset}"
    Write-Host "${CtpMauve}===============================================${Reset}`n"
}

try {
    # --- Main Batch Loop ---
    foreach ($Archive in $Archives) {
        $ArchiveStartTime = [datetime]::Now
        $Counter++
        $Percentage = [math]::Round(($Counter / $TotalFiles) * 100)

        # Elapsed / ETA based on archives completed so far
        $ElapsedTotal = [datetime]::Now - $ScriptStartTime
        if ($Counter -gt 1) {
            $CompletedSoFar  = $Counter - 1
            $AvgPerArchive   = $ElapsedTotal.TotalSeconds / $CompletedSoFar
            $RemainingCount  = $TotalFiles - $CompletedSoFar
            $ETASpan         = [TimeSpan]::FromSeconds($AvgPerArchive * $RemainingCount)
            $ProgressActivity = "ComicDiet Pipeline [$Counter/$TotalFiles | elapsed $(Format-Duration $ElapsedTotal) | ETA $(Format-Duration $ETASpan)]"
        } else {
            $ProgressActivity = "ComicDiet Pipeline [$Counter/$TotalFiles | calculating ETA...]"
        }
        Write-Progress -Activity $ProgressActivity -Status "Processing: $($Archive.Name)" -PercentComplete $Percentage

        # Portable Temporary Workspace (Bypasses AppData/UAC Heuristics)
        $TempDir = Join-Path $BaseTemp "$([guid]::NewGuid())"

        # Filename Sanitization & Collision Handling
        $CleanName = Get-CleanName $Archive.BaseName
        $FinalOutPath = Join-Path $OutputDir "$CleanName.cbz"
        $CollisionIndex = 1
        while (Test-Path $FinalOutPath) {
            $FinalOutPath = Join-Path $OutputDir "${CleanName}_${CollisionIndex}.cbz"
            $CollisionIndex++
        }

        try {
            New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
            $TotalOriginalBytes += $Archive.Length

            # Stage 1: Extraction
            Write-Host "${CtpPeach}[$Percentage%] $IcoExtract  EXTRACTING:${Reset} $($Archive.Name)"
            $ExtractArgs = "x `"$($Archive.FullName)`" -o`"$TempDir`" -p- -y -bso0 -bsp0"
            $extProcess = Start-Process -FilePath $PathTo7z -ArgumentList $ExtractArgs -Wait -NoNewWindow -PassThru
            if ($extProcess.ExitCode -ne 0) { throw "Extraction failed or archive is password-protected." }

            # Stage 2: Sanitization
            Write-Host "${CtpOverlay0}[$Percentage%] $IcoSanitize  SANITIZING: Purging system artifacts...${Reset}"
            Get-ChildItem -Path $TempDir -Include $JunkFiles -Recurse -Force -File | Remove-Item -Force
            Get-ChildItem -Path $TempDir -Directory -Filter "__MACOSX" -Recurse -Force | Remove-Item -Recurse -Force

            # Stage 3: WebP detection (pre-flight before optimization)
            # WebP files are not processed by Jpegli - they are preserved as-is.
            # The archive is still converted to CBZ format.
            $WebPFiles = @(Get-ChildItem -Path $TempDir -File -Recurse |
                Where-Object { $_.Extension.ToLower() -eq ".webp" })
            if ($WebPFiles.Count -gt 0) {
                Write-Host "${CtpTeal}[$Percentage%] $IcoWebP  INFO      :${Reset} $($WebPFiles.Count) WebP image(s) will be preserved as-is."
            }

            # Stage 4: Optimization
            $Images = Get-ChildItem -Path $TempDir -File -Recurse | Where-Object { $ImageExtensions -contains $_.Extension.ToLower() }
            $TotalImages = @($Images).Count
            Write-Host "${CtpSky}[$Percentage%] $IcoOptimize  OPTIMIZING:${Reset} Dispatching $TotalImages image(s) to Jpegli ($ThrottleLimit threads)..."

            $ProgressDict = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()
            $ProgressDict['Done'] = 0
            $ImageErrors = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

            $Images | ForEach-Object -Parallel {
                $Img   = $_
                $Ext   = $Img.Extension.ToLower()
                $total = $using:TotalImages

                # --- Alpha Channel Guard (PNG Pre-Flight) ---
                if ($Ext -eq ".png") {
                    $fs = $null
                    try {
                        $fs = [System.IO.File]::OpenRead($Img.FullName)
                        $bytes = New-Object byte[] 26
                        $bytesRead = $fs.Read($bytes, 0, 26)
                        if ($bytesRead -ge 26) {
                            $colorType = $bytes[25]
                            if ($colorType -in 4, 6) { return }
                        }
                    } catch {
                        return
                    } finally {
                        if ($null -ne $fs) { $fs.Close(); $fs.Dispose() }
                    }
                }

                # --- Execution Definition ---
                $OutFile = Join-Path $Img.DirectoryName "$($Img.BaseName)_opt.jpg"
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $using:PathToCjpegli
                $psi.Arguments = "`"$($Img.FullName)`" `"$OutFile`" -d 1.0 --chroma_subsampling=444"
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true

                $p = $null
                try {
                    $p = [System.Diagnostics.Process]::Start($psi)

                    try {
                        if (-not $p.HasExited) { $p.PriorityClass = 'BelowNormal' }
                    } catch { }

                    $stderrTask = $p.StandardError.ReadToEndAsync()
                    $stdoutTask = $p.StandardOutput.ReadToEndAsync()

                    if (-not $p.WaitForExit(60000)) {
                        $p.Kill()
                        throw "Timeout (60s)"
                    }

                    $stderr = $stderrTask.Result
                    $null = $stdoutTask.Result

                    if ($p.ExitCode -ne 0) {
                        $cleanErr = if ([string]::IsNullOrWhiteSpace($stderr)) { "exit $($p.ExitCode)" } else { "exit $($p.ExitCode): $($stderr.Trim())" }
                        throw $cleanErr
                    }

                    # Size-Regression Guard: only commit Jpegli output if it's smaller.
                    # Preserves the original when Jpegli can't beat it (already-tight
                    # JPEGs, line-art, etc.). Prevents per-image size regressions.
                    if (Test-Path $OutFile) {
                        $InSize  = $Img.Length
                        $OutSize = (Get-Item $OutFile).Length

                        if ($OutSize -lt $InSize) {
                            Remove-Item $Img.FullName -Force
                            if ($Ext -eq ".png") {
                                Rename-Item $OutFile "$($Img.BaseName).jpg" -Force
                            } else {
                                Rename-Item $OutFile $Img.Name -Force
                            }
                        } else {
                            Remove-Item $OutFile -Force
                        }
                    }
                } catch {
                    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
                    $errMsg = "IMG: $($Img.FullName) -> $_"
                    ($using:ImageErrors).Enqueue($errMsg)
                } finally {
                    if ($null -ne $p) { $p.Dispose() }

                    [void]($using:ProgressDict).AddOrUpdate('Done', 1, { param($key, $oldVal) $oldVal + 1 })
                    $done = ($using:ProgressDict)['Done']

                    if ($total -gt 0) {
                        $pct = [math]::Round(($done / $total) * 100)

                        # Throttle UI refreshes to prevent buffer tearing
                        if ($done % 5 -eq 0 -or $done -eq $total) {
                            Write-Progress -Activity "Image Optimization" -Status "Encoding... ($done / $total)" -PercentComplete $pct -Id 2
                        }
                    }
                }

            } -ThrottleLimit $ThrottleLimit
            Write-Progress -Activity "Image Optimization" -Completed -Id 2

            # Flush per-image error queue to log (Capped at 5, single batched write)
            if ($ImageErrors.Count -gt 0) {
                $ErrorArray   = $ImageErrors.ToArray()
                $ErrorCap     = 5
                $DisplayCount = [math]::Min($ErrorArray.Count, $ErrorCap)

                $LogLines = New-Object System.Collections.Generic.List[string]
                $LogLines.Add("[$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] Archive: $($Archive.FullName) -> $($ImageErrors.Count) image error(s)")

                for ($i = 0; $i -lt $DisplayCount; $i++) {
                    $LogLines.Add("  $($ErrorArray[$i])")
                }

                if ($ErrorArray.Count -gt $ErrorCap) {
                    $Suppressed = $ErrorArray.Count - $ErrorCap
                    $LogLines.Add("  ...and $Suppressed additional image errors suppressed.")
                }

                Add-Content -Path $ErrorLogPath -Value $LogLines
            }

            # Defensive sweep: guarantee no _opt.jpg leftovers reach the repack.
            # Covers race conditions where the parallel block's Remove-Item lost
            # to a transient file lock (AV scanning the freshly-written file).
            $LeftoverOpt = Get-ChildItem -Path $TempDir -Filter "*_opt.jpg" -Recurse -File -ErrorAction SilentlyContinue
            if ($LeftoverOpt) {
                $LeftoverOpt | Remove-Item -Force -ErrorAction SilentlyContinue
            }

            # Stage 5: Repacking
            Write-Host "${CtpLavender}[$Percentage%] $IcoRepack  REPACKING :${Reset} $($Archive.Name)"
            $PackArgs = "a -tzip `"$FinalOutPath`" `".\*`" -mx0 -bso0 -bsp0"
            $packProcess = Start-Process -FilePath $PathTo7z -ArgumentList $PackArgs -WorkingDirectory $TempDir -Wait -NoNewWindow -PassThru
            if ($packProcess.ExitCode -ne 0) { throw "Repacking failure." }

            # Success Telemetry
            $FinalSize = (Get-Item $FinalOutPath).Length
            $TotalOptimizedBytes += $FinalSize
            $SuccessCount++
            $SuccessfulOriginals.Add($Archive.FullName)

            $ArchiveDuration  = Format-Duration ([datetime]::Now - $ArchiveStartTime)
            $ArchiveInMB      = [math]::Round($Archive.Length / 1MB, 2)
            $ArchiveOutMB     = [math]::Round($FinalSize / 1MB, 2)
            $ArchivePctSaved  = if ($Archive.Length -gt 0) { [math]::Round((($Archive.Length - $FinalSize) / $Archive.Length) * 100, 1) } else { 0 }
            $PctDisplay       = if ($ArchivePctSaved -ge 0) { "-$ArchivePctSaved%" } else { "+$([math]::Abs($ArchivePctSaved))%" }
            $ImgErrMarker     = if ($ImageErrors.Count -gt 0) { " ${CtpYellow}($($ImageErrors.Count) image errors)${Reset}" } else { "" }

            Write-Host "${CtpGreen}[$Percentage%] $IcoSuccess  SUCCESS [$ArchiveDuration]:${Reset} $(Split-Path -Leaf $FinalOutPath) ${CtpOverlay0}($ArchiveInMB MB > $ArchiveOutMB MB, $PctDisplay)${Reset}$ImgErrMarker`n"

        } catch {
            # Archive-level error logging
            $FailCount++
            $reason = ("$_" -replace "\s+", " ").Trim()
            $FailedArchives.Add([PSCustomObject]@{ Name = $Archive.Name; Reason = $reason })
            $ErrorMessage = "[$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] ARCHIVE: $($Archive.FullName): $_"
            Add-Content -Path $ErrorLogPath -Value $ErrorMessage
            $ArchiveDuration = Format-Duration ([datetime]::Now - $ArchiveStartTime)
            Write-Host "${CtpRed}[$Percentage%] $IcoFailed  FAILED  [$ArchiveDuration]:${Reset} $($Archive.Name). Check error log.`n"
        } finally {
            # Drive-Aware Cleanup
            if (Test-Path $TempDir) {
                Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # --- Post-Batch: Recycle Originals of Successful Conversions ---
    if (-not $KeepOriginals -and $SuccessfulOriginals.Count -gt 0) {
        Write-Host "${CtpYellow}[*] $IcoTrash  Moving $($SuccessfulOriginals.Count) original archive(s) to Recycle Bin...${Reset}"
        foreach ($origPath in $SuccessfulOriginals) {
            try {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $origPath,
                    'OnlyErrorDialogs',
                    'SendToRecycleBin'
                )
                $TrashCount++
            } catch {
                $TrashFailures++
                Add-Content -Path $ErrorLogPath -Value "[$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] RECYCLE FAILED: $origPath -> $_"
            }
        }
    }
}
finally {
    # Guarantees summary on normal exit, Ctrl+C, or unhandled exceptions.
    Write-ComicDietSummary
}
