#Requires -Version 7.4
<#
.SYNOPSIS
    ComicDiet GUI - Drag-and-drop interface for ComicDiet.ps1
.DESCRIPTION
    WinForms wrapper that lets you drag a folder (or browse for one),
    configure flags, and run ComicDiet.ps1 with live log output.
    Requires ComicDiet.ps1 in the same folder.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -------------------------------------------------------------------------
# Dracula palette (hex, for WinForms Color objects)
# -------------------------------------------------------------------------
function DrC([string]$hex) {
    [System.Drawing.ColorTranslator]::FromHtml($hex)
}

$BG        = DrC "#282A36"  # Background
$BgSurface = DrC "#383A59"  # Slightly lighter surface (drop zone, panels)
$BgInput   = DrC "#1E1F2E"  # Input fields
$FgText    = DrC "#F8F8F2"  # Foreground
$ColPink   = DrC "#FF79C6"  # Accent / borders
$ColCyan   = DrC "#8BE9FD"  # Secondary accent
$ColGreen  = DrC "#50FA7B"  # Success
$ColRed    = DrC "#FF5555"  # Error
$ColYellow = DrC "#F1FA8C"  # Warning
$ColDim    = DrC "#6272A4"  # Subdued

# -------------------------------------------------------------------------
# Paths
# -------------------------------------------------------------------------
$ScriptDir   = $PSScriptRoot
$MainScript  = Join-Path $ScriptDir "ComicDiet.ps1"

if (-not (Test-Path $MainScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "ComicDiet.ps1 not found in:`n$ScriptDir`n`nPlace ComicDiet-GUI.ps1 in the same folder as ComicDiet.ps1.",
        "ComicDiet - Missing Script",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# -------------------------------------------------------------------------
# Font
# -------------------------------------------------------------------------
$FontMono  = [System.Drawing.Font]::new("Cascadia Mono", 9)
$FontMonoS = [System.Drawing.Font]::new("Cascadia Mono", 8)
$FontUI    = [System.Drawing.Font]::new("Segoe UI", 9)
$FontUIB   = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$FontBig   = [System.Drawing.Font]::new("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)

# Fallback: Cascadia Mono may not be installed
$installedFonts = [System.Drawing.Text.InstalledFontCollection]::new().Families | Select-Object -ExpandProperty Name
if ("Cascadia Mono" -notin $installedFonts) {
    $FontMono  = [System.Drawing.Font]::new("Consolas", 9)
    $FontMonoS = [System.Drawing.Font]::new("Consolas", 8)
}

# -------------------------------------------------------------------------
# Form
# -------------------------------------------------------------------------
$Form                  = [System.Windows.Forms.Form]::new()
$Form.Text             = "ComicDiet"
$Form.Size             = [System.Drawing.Size]::new(780, 620)
$Form.MinimumSize      = [System.Drawing.Size]::new(660, 520)
$Form.StartPosition    = "CenterScreen"
$Form.BackColor        = $BG
$Form.ForeColor        = $FgText
$Form.Font             = $FontUI
$Form.FormBorderStyle  = "Sizable"

# -------------------------------------------------------------------------
# Title bar area
# -------------------------------------------------------------------------
$PanelTop            = [System.Windows.Forms.Panel]::new()
$PanelTop.Dock       = "Top"
$PanelTop.Height     = 54
$PanelTop.BackColor  = $BG
$PanelTop.Padding    = [System.Windows.Forms.Padding]::new(16, 0, 16, 0)

$LblTitle            = [System.Windows.Forms.Label]::new()
$LblTitle.Text       = "ComicDiet"
$LblTitle.Font       = [System.Drawing.Font]::new("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$LblTitle.ForeColor  = $ColPink
$LblTitle.AutoSize   = $true
$LblTitle.Location   = [System.Drawing.Point]::new(16, 10)

$LblSub              = [System.Windows.Forms.Label]::new()
$LblSub.Text         = "Comic Archive Optimizer"
$LblSub.Font         = $FontUI
$LblSub.ForeColor    = $ColDim
$LblSub.AutoSize     = $true
$LblSub.Location     = [System.Drawing.Point]::new(160, 20)

$PanelTop.Controls.AddRange(@($LblTitle, $LblSub))

# -------------------------------------------------------------------------
# Drop zone
# -------------------------------------------------------------------------
$PanelDrop                  = [System.Windows.Forms.Panel]::new()
$PanelDrop.Height           = 90
$PanelDrop.Dock             = "Top"
$PanelDrop.Margin           = [System.Windows.Forms.Padding]::new(16, 0, 16, 0)
$PanelDrop.Padding          = [System.Windows.Forms.Padding]::new(16, 8, 16, 8)
$PanelDrop.BackColor        = $BgSurface
$PanelDrop.AllowDrop        = $true

$LblDropHint                = [System.Windows.Forms.Label]::new()
$LblDropHint.Text           = "Drop a folder here  --  or browse below"
$LblDropHint.Font           = [System.Drawing.Font]::new("Segoe UI", 11)
$LblDropHint.ForeColor      = $ColDim
$LblDropHint.TextAlign      = "MiddleCenter"
$LblDropHint.Dock           = "Fill"
$LblDropHint.AllowDrop      = $true

$PanelDrop.Controls.Add($LblDropHint)

# Drop events on both panel and label
$DropHandler = {
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $dropped = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        $first   = $dropped[0]
        if (Test-Path $first -PathType Container) {
            $TxtTarget.Text     = $first
            $PanelDrop.BackColor = $BgSurface
            $LblDropHint.ForeColor = $ColCyan
            $LblDropHint.Text   = "Folder ready: $([System.IO.Path]::GetFileName($first))"
        } else {
            $LblDropHint.ForeColor = $ColYellow
            $LblDropHint.Text   = "Drop a folder, not a file."
        }
    }
}

$DragEnterHandler = {
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        $PanelDrop.BackColor = DrC "#44475A"
    } else {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::None
    }
}

$DragLeaveHandler = {
    $PanelDrop.BackColor = $BgSurface
}

$PanelDrop.Add_DragDrop($DropHandler)
$PanelDrop.Add_DragEnter($DragEnterHandler)
$PanelDrop.Add_DragLeave($DragLeaveHandler)
$LblDropHint.Add_DragDrop($DropHandler)
$LblDropHint.Add_DragEnter($DragEnterHandler)
$LblDropHint.Add_DragLeave($DragLeaveHandler)

# -------------------------------------------------------------------------
# Target folder row
# -------------------------------------------------------------------------
$PanelTarget              = [System.Windows.Forms.Panel]::new()
$PanelTarget.Height       = 38
$PanelTarget.Dock         = "Top"
$PanelTarget.Padding      = [System.Windows.Forms.Padding]::new(16, 4, 16, 4)
$PanelTarget.BackColor    = $BG

$TxtTarget                = [System.Windows.Forms.TextBox]::new()
$TxtTarget.PlaceholderText = "C:\Comics\Unread"
$TxtTarget.Font           = $FontMono
$TxtTarget.BackColor      = $BgInput
$TxtTarget.ForeColor      = $FgText
$TxtTarget.BorderStyle    = "FixedSingle"
$TxtTarget.Height         = 26
$TxtTarget.Anchor         = "Left,Right,Top"
$TxtTarget.Location       = [System.Drawing.Point]::new(16, 6)
$TxtTarget.Width          = 580

$BtnBrowse                = [System.Windows.Forms.Button]::new()
$BtnBrowse.Text           = "Browse..."
$BtnBrowse.Font           = $FontUI
$BtnBrowse.BackColor      = $BgSurface
$BtnBrowse.ForeColor      = $FgText
$BtnBrowse.FlatStyle      = "Flat"
$BtnBrowse.FlatAppearance.BorderColor = $ColDim
$BtnBrowse.Height         = 26
$BtnBrowse.Width          = 90
$BtnBrowse.Anchor         = "Right,Top"
$BtnBrowse.Location       = [System.Drawing.Point]::new(614, 6)
$BtnBrowse.Cursor         = "Hand"

$BtnBrowse.Add_Click({
    $Dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $Dialog.Description = "Select the folder containing comic archives"
    if ($TxtTarget.Text -and (Test-Path $TxtTarget.Text)) {
        $Dialog.SelectedPath = $TxtTarget.Text
    }
    if ($Dialog.ShowDialog() -eq "OK") {
        $TxtTarget.Text = $Dialog.SelectedPath
        $LblDropHint.ForeColor = $ColCyan
        $LblDropHint.Text = "Folder ready: $([System.IO.Path]::GetFileName($Dialog.SelectedPath))"
    }
})

$PanelTarget.Controls.AddRange(@($TxtTarget, $BtnBrowse))

# Resize handler so TxtTarget stretches with the form
$Form.Add_Resize({
    $TxtTarget.Width  = $PanelTarget.Width - 16 - 90 - 24
    $BtnBrowse.Left   = $PanelTarget.Width - 90 - 16
})

# -------------------------------------------------------------------------
# Options row
# -------------------------------------------------------------------------
$PanelOpts            = [System.Windows.Forms.Panel]::new()
$PanelOpts.Height     = 34
$PanelOpts.Dock       = "Top"
$PanelOpts.Padding    = [System.Windows.Forms.Padding]::new(16, 4, 16, 4)
$PanelOpts.BackColor  = $BG

$ChkDryRun                  = [System.Windows.Forms.CheckBox]::new()
$ChkDryRun.Text             = "Dry Run"
$ChkDryRun.ForeColor        = $FgText
$ChkDryRun.AutoSize         = $true
$ChkDryRun.Location         = [System.Drawing.Point]::new(16, 8)
$ChkDryRun.Cursor           = "Hand"

$ChkKeepOriginals            = [System.Windows.Forms.CheckBox]::new()
$ChkKeepOriginals.Text      = "Keep Originals"
$ChkKeepOriginals.ForeColor = $FgText
$ChkKeepOriginals.AutoSize  = $true
$ChkKeepOriginals.Location  = [System.Drawing.Point]::new(110, 8)
$ChkKeepOriginals.Cursor    = "Hand"

$LblOptsHint                = [System.Windows.Forms.Label]::new()
$LblOptsHint.Text           = "Optimized archives saved to 'Optimized Comics' inside the target folder."
$LblOptsHint.ForeColor      = $ColDim
$LblOptsHint.Font           = [System.Drawing.Font]::new("Segoe UI", 8)
$LblOptsHint.AutoSize       = $true
$LblOptsHint.Location       = [System.Drawing.Point]::new(260, 10)

$PanelOpts.Controls.AddRange(@($ChkDryRun, $ChkKeepOriginals, $LblOptsHint))

# -------------------------------------------------------------------------
# Run button
# -------------------------------------------------------------------------
$PanelRun             = [System.Windows.Forms.Panel]::new()
$PanelRun.Height      = 46
$PanelRun.Dock        = "Top"
$PanelRun.Padding     = [System.Windows.Forms.Padding]::new(16, 6, 16, 6)
$PanelRun.BackColor   = $BG

$BtnRun               = [System.Windows.Forms.Button]::new()
$BtnRun.Text          = "Run ComicDiet"
$BtnRun.Font          = $FontUIB
$BtnRun.BackColor     = $ColPink
$BtnRun.ForeColor     = $BG
$BtnRun.FlatStyle     = "Flat"
$BtnRun.FlatAppearance.BorderSize = 0
$BtnRun.Height        = 34
$BtnRun.Width         = 160
$BtnRun.Location      = [System.Drawing.Point]::new(16, 6)
$BtnRun.Cursor        = "Hand"

$BtnClear             = [System.Windows.Forms.Button]::new()
$BtnClear.Text        = "Clear Log"
$BtnClear.Font        = $FontUI
$BtnClear.BackColor   = $BgSurface
$BtnClear.ForeColor   = $FgText
$BtnClear.FlatStyle   = "Flat"
$BtnClear.FlatAppearance.BorderColor = $ColDim
$BtnClear.Height      = 34
$BtnClear.Width       = 90
$BtnClear.Location    = [System.Drawing.Point]::new(184, 6)
$BtnClear.Cursor      = "Hand"
$BtnClear.Add_Click({ $TxtLog.Clear() })

$LblStatus            = [System.Windows.Forms.Label]::new()
$LblStatus.Text       = "Ready."
$LblStatus.ForeColor  = $ColDim
$LblStatus.Font       = $FontUI
$LblStatus.AutoSize   = $true
$LblStatus.Location   = [System.Drawing.Point]::new(288, 16)

$PanelRun.Controls.AddRange(@($BtnRun, $BtnClear, $LblStatus))

# -------------------------------------------------------------------------
# Log output
# -------------------------------------------------------------------------
$TxtLog               = [System.Windows.Forms.RichTextBox]::new()
$TxtLog.Dock          = "Fill"
$TxtLog.BackColor     = $BgInput
$TxtLog.ForeColor     = $FgText
$TxtLog.Font          = $FontMonoS
$TxtLog.ReadOnly      = $true
$TxtLog.BorderStyle   = "None"
$TxtLog.ScrollBars    = "Vertical"
$TxtLog.WordWrap      = $false
$TxtLog.Padding       = [System.Windows.Forms.Padding]::new(8)

# -------------------------------------------------------------------------
# Separator
# -------------------------------------------------------------------------
$Sep                  = [System.Windows.Forms.Panel]::new()
$Sep.Height           = 1
$Sep.Dock             = "Top"
$Sep.BackColor        = $ColDim

# -------------------------------------------------------------------------
# Log helpers: strip ANSI escape sequences, color key lines
# -------------------------------------------------------------------------
$AnsiRegex = [System.Text.RegularExpressions.Regex]::new('\x1B\[[0-9;]*m')

function Add-LogLine([string]$raw) {
    $line = $AnsiRegex.Replace($raw, "").TrimEnd()
    if (-not $line) { return }

    $color = $FgText
    if     ($line -match "OK\s+SUCCESS")    { $color = $ColGreen  }
    elseif ($line -match "XX\s+FAILED")     { $color = $ColRed    }
    elseif ($line -match ">>\s+EXTRACTING") { $color = DrC "#FFB86C" }
    elseif ($line -match "\*\*\s+OPTIMIZING"){ $color = $ColCyan  }
    elseif ($line -match "##\s+REPACKING")  { $color = DrC "#BD93F9" }
    elseif ($line -match "::\s+SANITIZING") { $color = $ColDim    }
    elseif ($line -match "^=+$")            { $color = $ColPink   }
    elseif ($line -match "Space Reclaimed|Total Reduction") { $color = $ColGreen }
    elseif ($line -match "FAILED|XX\s|error") { $color = $ColRed  }
    elseif ($line -match "~~\s+Moving")     { $color = $ColYellow }
    elseif ($line -match "BATCH SUMMARY|RUN INITIALIZED|SETUP") { $color = $ColCyan }

    $TxtLog.SelectionStart  = $TxtLog.TextLength
    $TxtLog.SelectionLength = 0
    $TxtLog.SelectionColor  = $color
    $TxtLog.AppendText("$line`n")
    $TxtLog.ScrollToCaret()
}

# -------------------------------------------------------------------------
# Run logic
# -------------------------------------------------------------------------
$RunJob = $null

$BtnRun.Add_Click({
    $target = $TxtTarget.Text.Trim()

    if (-not $target) {
        $LblStatus.ForeColor = $ColYellow
        $LblStatus.Text      = "Drop or browse to a folder first."
        return
    }

    if (-not (Test-Path $target -PathType Container)) {
        $LblStatus.ForeColor = $ColRed
        $LblStatus.Text      = "Folder not found."
        return
    }

    # Build argument list
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$MainScript`"", "-Target", "`"$target`"")
    if ($ChkDryRun.Checked)        { $argList += "-DryRun" }
    if ($ChkKeepOriginals.Checked) { $argList += "-KeepOriginals" }

    $BtnRun.Enabled      = $false
    $BtnRun.Text         = "Running..."
    $LblStatus.ForeColor = $ColCyan
    $LblStatus.Text      = "Processing..."
    $TxtLog.Clear()

    Add-LogLine ">> Starting ComicDiet on: $target"
    Add-LogLine ""

    # Run in a background job so the UI stays responsive
    $script:RunJob = Start-Job -ScriptBlock {
        param($pwshPath, $argList)
        & $pwshPath @argList 2>&1
    } -ArgumentList (Get-Command pwsh).Source, $argList

    # Poll the job output every 250ms via a Timer
    $Timer          = [System.Windows.Forms.Timer]::new()
    $Timer.Interval = 250

    $Timer.Add_Tick({
        # Drain available output
        $lines = Receive-Job -Job $script:RunJob 2>&1
        foreach ($line in $lines) {
            Add-LogLine "$line"
        }

        # Check if job is done
        if ($script:RunJob.State -in @("Completed", "Failed", "Stopped")) {
            $Timer.Stop()
            $Timer.Dispose()

            # Final drain
            $remaining = Receive-Job -Job $script:RunJob 2>&1
            foreach ($line in $remaining) { Add-LogLine "$line" }
            Remove-Job -Job $script:RunJob -Force

            $BtnRun.Enabled  = $true
            $BtnRun.Text     = "Run ComicDiet"

            if ($script:RunJob.State -eq "Completed") {
                $LblStatus.ForeColor = $ColGreen
                $LblStatus.Text      = "Done."
            } else {
                $LblStatus.ForeColor = $ColRed
                $LblStatus.Text      = "Job ended with errors."
            }
            $script:RunJob = $null
        }
    })

    $Timer.Start()
})

# -------------------------------------------------------------------------
# Assemble form (Top-docked panels stack top-to-bottom; Fill takes the rest)
# -------------------------------------------------------------------------
# Add in reverse order for correct Top-docking stack
$Form.Controls.Add($TxtLog)
$Form.Controls.Add($Sep)
$Form.Controls.Add($PanelRun)
$Form.Controls.Add($PanelOpts)
$Form.Controls.Add($PanelTarget)
$Form.Controls.Add($PanelDrop)
$Form.Controls.Add($PanelTop)

# -------------------------------------------------------------------------
# Guard: warn if ComicDiet.ps1 prerequisites look missing
# -------------------------------------------------------------------------
$Form.Add_Shown({
    $missing = @()
    if (-not (Test-Path "C:\Program Files\7-Zip\7z.exe")) { $missing += "7-Zip" }
    if (-not (Test-Path (Join-Path $ScriptDir "cjpegli.exe")))  { $missing += "cjpegli.exe" }

    if ($missing.Count -gt 0) {
        Add-LogLine "!! Missing dependencies: $($missing -join ', ')"
        Add-LogLine "   Run Install.bat to set up ComicDiet before using the GUI."
        Add-LogLine ""
        $LblStatus.ForeColor = $ColYellow
        $LblStatus.Text      = "Run Install.bat first."
    } else {
        Add-LogLine ">> ComicDiet ready. Drop a folder or browse to get started."
        Add-LogLine ""
    }
})

# -------------------------------------------------------------------------
# Close guard: confirm if a job is running
# -------------------------------------------------------------------------
$Form.Add_FormClosing({
    param($s, $e)
    if ($null -ne $script:RunJob -and $script:RunJob.State -eq "Running") {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "ComicDiet is still running. Close anyway?",
            "ComicDiet",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -eq "No") {
            $e.Cancel = $true
        } else {
            Stop-Job  -Job $script:RunJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:RunJob -ErrorAction SilentlyContinue
        }
    }
})

[System.Windows.Forms.Application]::Run($Form)
