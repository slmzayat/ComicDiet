#Requires -Version 7.4
<#
.SYNOPSIS
    ComicDiet - Comic Archive Optimizer (primary entry point)
.DESCRIPTION
    Drag-and-drop GUI for ComicDiet. Accepts folders and individual archives.
    Launches ComicDiet-CLI.ps1 as the optimization engine.

    Accepts an optional -Source parameter so it can be launched from the
    Windows Explorer context menu with a folder pre-populated.
#>

param(
    # Optional: pre-populate source field (used by the Explorer context menu).
    [string]$Source = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -------------------------------------------------------------------------
# Catppuccin Mocha palette
# Variable names follow the official Catppuccin style guide:
# https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md
# Mauve is the primary accent (per the style guide's default).
# -------------------------------------------------------------------------
function CtpC([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

# Surface hierarchy: Crust < Mantle < Base < Surface0 < Surface1 < Surface2
$CtpBase     = CtpC "#1e1e2e"   # main window background
$CtpMantle   = CtpC "#181825"   # inputs, log area
$CtpSurface0 = CtpC "#313244"   # raised surfaces, log header
$CtpSurface1 = CtpC "#45475a"   # hover / drag-over state

# Text hierarchy: Text > Subtext1 > Subtext0 > Overlay2 > Overlay1 > Overlay0
$CtpText     = CtpC "#cdd6f4"   # primary text  - AAA on all surfaces
$CtpSubtext0 = CtpC "#a6adc8"   # muted text    - AA on all surfaces
$CtpOverlay0 = CtpC "#6c7086"   # decorative only (separators, borders)

# Accents - per style guide, Mauve is the default brand accent
$CtpMauve    = CtpC "#cba6f7"   # primary brand / borders / title
$CtpLavender = CtpC "#b4befe"   # secondary accent / repack phase
$CtpSky      = CtpC "#89dceb"   # headers / optimize phase
$CtpGreen    = CtpC "#a6e3a1"   # success
$CtpRed      = CtpC "#f38ba8"   # errors
$CtpYellow   = CtpC "#f9e2af"   # warnings
$CtpPeach    = CtpC "#fab387"   # extract phase
$CtpTeal     = CtpC "#94e2d5"   # informational (WebP notice - matches CLI)

# -------------------------------------------------------------------------
# Paths
# -------------------------------------------------------------------------
$ScriptDir          = $PSScriptRoot
$MainScript         = Join-Path $ScriptDir "ComicDiet-CLI.ps1"
$SupportedExts      = @(".cbr", ".cbz", ".cb7", ".cbt")  # mirrors ComicDiet-CLI.ps1
$script:SelectedItems = @()   # holds validated paths (folders and/or files)

if (-not (Test-Path $MainScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "ComicDiet-CLI.ps1 not found in:`n$ScriptDir`n`nPlace ComicDiet.ps1 and ComicDiet-CLI.ps1 in the same folder.",
        "ComicDiet",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# -------------------------------------------------------------------------
# Fonts
# -------------------------------------------------------------------------
$installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
$monoFace  = if ("Cascadia Mono" -in $installed) { "Cascadia Mono" } else { "Consolas" }
$FontUI    = [System.Drawing.Font]::new("Segoe UI",  9)
$FontUIB   = [System.Drawing.Font]::new("Segoe UI",  9, [System.Drawing.FontStyle]::Bold)
$FontMono  = [System.Drawing.Font]::new($monoFace,   9)
$FontMonoS = [System.Drawing.Font]::new($monoFace,   8)
$FontSmall = [System.Drawing.Font]::new("Segoe UI",  8)
$FontLog   = [System.Drawing.Font]::new("Segoe UI",  8)

# -------------------------------------------------------------------------
# Tooltips
# -------------------------------------------------------------------------
$Tips = [System.Windows.Forms.ToolTip]::new()
$Tips.InitialDelay = 400
$Tips.ReshowDelay  = 200

# -------------------------------------------------------------------------
# Selection state helper
# Single source of truth for all input paths. Called by every selection
# entry-point (drag-drop, browse, typed path) to keep state consistent.
# -------------------------------------------------------------------------
function Update-Selection([string[]]$items) {
    $script:SelectedItems = @($items | Where-Object { $_ -and (Test-Path $_) })
    $count = $script:SelectedItems.Count

    if ($count -eq 0) {
        $TxtSource.Text        = ""
        $BtnRun.Enabled        = $false
        $StatusLabel.ForeColor = $CtpSubtext0
        $StatusLabel.Text      = "Ready"
        return
    }

    if ($count -eq 1) {
        $TxtSource.Text        = $script:SelectedItems[0]
        $name = [System.IO.Path]::GetFileName($script:SelectedItems[0])
        $StatusLabel.ForeColor = $CtpSky
        $StatusLabel.Text      = "Source: $name"
    } else {
        $TxtSource.Text        = "$count archives selected"
        $name = [System.IO.Path]::GetFileName($script:SelectedItems[0])
        $StatusLabel.ForeColor = $CtpSky
        $StatusLabel.Text      = "$count archives selected  -  first: $name"
    }
    $BtnRun.Enabled = $true
}

# -------------------------------------------------------------------------
# Form
# -------------------------------------------------------------------------
$Form                 = [System.Windows.Forms.Form]::new()
$Form.Text            = "ComicDiet"
$Form.Size            = [System.Drawing.Size]::new(800, 560)
$Form.MinimumSize     = [System.Drawing.Size]::new(660, 440)
$Form.StartPosition   = "CenterScreen"
$Form.BackColor       = $CtpBase
$Form.ForeColor       = $CtpText
$Form.Font            = $FontUI
$Form.FormBorderStyle = "Sizable"
$Form.KeyPreview      = $true
$Form.AllowDrop       = $true   # whole window is a drop target

# ── Window icon ──────────────────────────────────────────────────────────────
# Checks for ComicDiet.ico next to this script (user-supplied custom icon).
# Falls back to extracting an icon from imageres.dll (ships on every Windows).
# Fails silently so a missing icon never crashes the GUI.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
    [DllImport("shell32.dll", CharSet=CharSet.Auto)]
    public static extern uint ExtractIconEx(string szFileName, int nIconIndex,
        IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);
}
'@ -ErrorAction SilentlyContinue

try {
    $customIco = Join-Path $PSScriptRoot "ComicDiet.ico"
    if (Test-Path $customIco) {
        $Form.Icon = [System.Drawing.Icon]::new($customIco)
    } else {
        $imgRes = Join-Path $env:SystemRoot "System32\imageres.dll"
        $large  = [IntPtr[]]::new(1)
        $small  = [IntPtr[]]::new(1)
        $count  = [NativeIcon]::ExtractIconEx($imgRes, 13, $large, $small, 1)
        if ($count -gt 0 -and $large[0] -ne [IntPtr]::Zero) {
            $Form.Icon = [System.Drawing.Icon]::FromHandle($large[0])
        }
    }
} catch { }

# -------------------------------------------------------------------------
# Keyboard shortcuts
# -------------------------------------------------------------------------
$Form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq "Return" -and $BtnRun.Enabled) {
        $BtnRun.PerformClick()
        $e.SuppressKeyPress = $true
    }
    if ($e.KeyCode -eq "Escape") {
        $TxtLog.Focus()
        $e.SuppressKeyPress = $true
    }
})

# -------------------------------------------------------------------------
# StatusStrip (bottom of window)
# -------------------------------------------------------------------------
$StatusStrip           = [System.Windows.Forms.StatusStrip]::new()
$StatusStrip.BackColor = $CtpMantle
$StatusStrip.SizingGrip = $true

$StatusLabel           = [System.Windows.Forms.ToolStripStatusLabel]::new()
$StatusLabel.Text      = "Ready"
$StatusLabel.ForeColor = $CtpSubtext0
$StatusLabel.Font      = $FontSmall
$StatusLabel.Spring    = $true
$StatusLabel.TextAlign = "MiddleLeft"

$StatusTime            = [System.Windows.Forms.ToolStripStatusLabel]::new()
$StatusTime.Text       = ""
$StatusTime.ForeColor  = $CtpSubtext0
$StatusTime.Font       = $FontSmall
$StatusTime.TextAlign  = "MiddleRight"

$StatusStrip.Items.AddRange(@($StatusLabel, $StatusTime))

# -------------------------------------------------------------------------
# Title row
# -------------------------------------------------------------------------
$PanelTop           = [System.Windows.Forms.Panel]::new()
$PanelTop.Dock      = "Top"
$PanelTop.Height    = 52
$PanelTop.BackColor = $CtpBase

$LblTitle           = [System.Windows.Forms.Label]::new()
$LblTitle.Text      = "ComicDiet"
$LblTitle.Font      = [System.Drawing.Font]::new("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$LblTitle.ForeColor = $CtpMauve
$LblTitle.AutoSize  = $true
$LblTitle.Location  = [System.Drawing.Point]::new(16, 8)

$LblSub             = [System.Windows.Forms.Label]::new()
$LblSub.Text        = "Comic Archive Optimizer"
$LblSub.Font        = $FontUI
$LblSub.ForeColor   = $CtpSubtext0
$LblSub.AutoSize    = $true
$LblSub.Location    = [System.Drawing.Point]::new(164, 20)

$PanelTop.Controls.AddRange(@($LblTitle, $LblSub))

# -------------------------------------------------------------------------
# Source folder row
# Layout: [Label] / [Textbox ................] [Browse] / [Helper text]
# The entire form accepts drag-and-drop; folder path lands in TxtSource.
# -------------------------------------------------------------------------
$PanelFolder           = [System.Windows.Forms.Panel]::new()
$PanelFolder.Dock      = "Top"
$PanelFolder.Height    = 72
$PanelFolder.BackColor = $CtpBase
$PanelFolder.Padding   = [System.Windows.Forms.Padding]::new(16, 6, 16, 4)

$LblSourceCaption           = [System.Windows.Forms.Label]::new()
$LblSourceCaption.Text      = "Source folder"
$LblSourceCaption.Font      = $FontSmall
$LblSourceCaption.ForeColor = $CtpSubtext0
$LblSourceCaption.AutoSize  = $true
$LblSourceCaption.Location  = [System.Drawing.Point]::new(16, 6)

$TxtSource                  = [System.Windows.Forms.TextBox]::new()
$TxtSource.PlaceholderText  = "Drag a folder here or click Browse..."
$TxtSource.Font             = $FontMono
$TxtSource.BackColor        = $CtpMantle
$TxtSource.ForeColor        = $CtpText
$TxtSource.BorderStyle      = "FixedSingle"
$TxtSource.Height           = 26
$TxtSource.Anchor           = "Left,Right,Top"
$TxtSource.Location         = [System.Drawing.Point]::new(16, 24)
$TxtSource.Width            = 660
$TxtSource.AllowDrop        = $true   # also accepts drops directly

$BtnBrowse                  = [System.Windows.Forms.Button]::new()
$BtnBrowse.Text             = "Browse..."
$BtnBrowse.Font             = $FontUI
$BtnBrowse.BackColor        = $CtpSurface0
$BtnBrowse.ForeColor        = $CtpText
$BtnBrowse.FlatStyle        = "Flat"
$BtnBrowse.FlatAppearance.BorderColor = $CtpSubtext0
$BtnBrowse.Height           = 26
$BtnBrowse.Width            = 90
$BtnBrowse.Anchor           = "Right,Top"
$BtnBrowse.Location         = [System.Drawing.Point]::new(718, 24)
$BtnBrowse.Cursor           = "Hand"
$Tips.SetToolTip($BtnBrowse, "Open folder picker")

$LblHelper                  = [System.Windows.Forms.Label]::new()
$LblHelper.Text             = "Optimized archives are saved to an 'Optimized Comics' subfolder inside the source."
$LblHelper.Font             = $FontSmall
$LblHelper.ForeColor        = $CtpSubtext0
$LblHelper.AutoSize         = $true
$LblHelper.Location         = [System.Drawing.Point]::new(16, 54)

# Folder picker (option A: Browse stays folder-only; files via drag-and-drop)
$BtnBrowse.Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = "Select the folder containing comic archives"
    if ($script:SelectedItems.Count -eq 1 -and (Test-Path $script:SelectedItems[0] -PathType Container)) {
        $dlg.SelectedPath = $script:SelectedItems[0]
    }
    if ($dlg.ShowDialog() -eq "OK") {
        Update-Selection @($dlg.SelectedPath)
    }
})

# TextChanged: validate typed or pasted paths.
# Skips validation when text is our own display string ("N archives selected").
$TxtSource.Add_TextChanged({
    $val = $TxtSource.Text.Trim()
    if (-not $val -or $val -match "^\d+ archives selected$") { return }
    $isFolder = Test-Path $val -PathType Container
    $isFile   = (Test-Path $val -PathType Leaf) -and ($SupportedExts -contains [System.IO.Path]::GetExtension($val).ToLower())
    if ($isFolder -or $isFile) {
        Update-Selection @($val)
    } else {
        $BtnRun.Enabled = $false
    }
})

# Resize: stretch textbox, pin browse button
$PanelFolder.Add_Resize({
    $TxtSource.Width  = $PanelFolder.Width - 16 - 90 - 16 - 8
    $BtnBrowse.Left   = $PanelFolder.Width - 90 - 16
})

$PanelFolder.Controls.AddRange(@($LblSourceCaption, $TxtSource, $BtnBrowse, $LblHelper))

# -------------------------------------------------------------------------
# Options row  (checkboxes grouped left)
# -------------------------------------------------------------------------
$PanelOpts           = [System.Windows.Forms.Panel]::new()
$PanelOpts.Dock      = "Top"
$PanelOpts.Height    = 32
$PanelOpts.BackColor = $CtpBase
$PanelOpts.Padding   = [System.Windows.Forms.Padding]::new(16, 4, 16, 4)

$ChkKeepOriginals            = [System.Windows.Forms.CheckBox]::new()
$ChkKeepOriginals.Text       = "Keep Originals"
$ChkKeepOriginals.ForeColor  = $CtpText
$ChkKeepOriginals.AutoSize   = $true
$ChkKeepOriginals.Location   = [System.Drawing.Point]::new(16, 7)
$ChkKeepOriginals.Checked    = $true   # safe default: user must explicitly opt-in to trashing originals
$ChkKeepOriginals.Cursor     = "Hand"
$Tips.SetToolTip($ChkKeepOriginals, "Skip moving originals to the Recycle Bin after conversion.")

$PanelOpts.Controls.Add($ChkKeepOriginals)

# -------------------------------------------------------------------------
# Buttons row  (primary action left; Clear Log proximity-placed below)
# -------------------------------------------------------------------------
$PanelButtons           = [System.Windows.Forms.Panel]::new()
$PanelButtons.Dock      = "Top"
$PanelButtons.Height    = 44
$PanelButtons.BackColor = $CtpBase
$PanelButtons.Padding   = [System.Windows.Forms.Padding]::new(16, 6, 16, 6)

$BtnRun                 = [System.Windows.Forms.Button]::new()
$BtnRun.Text            = "Optimize Comics"
$BtnRun.Font            = $FontUIB
$BtnRun.BackColor       = $CtpMauve
$BtnRun.ForeColor       = $CtpBase
$BtnRun.FlatStyle       = "Flat"
$BtnRun.FlatAppearance.BorderSize = 0
$BtnRun.Height          = 32
$BtnRun.Width           = 160
$BtnRun.Location        = [System.Drawing.Point]::new(624, 6)
$BtnRun.Anchor          = "Top"
$BtnRun.Cursor          = "Hand"
$BtnRun.Enabled         = $false   # disabled until valid source path is set
$Tips.SetToolTip($BtnRun, "Start optimization  (Enter)")

# Right-align to match Browse button's right edge
$PanelButtons.Add_Resize({ $BtnRun.Left = $PanelButtons.Width - 16 - $BtnRun.Width })

$PanelButtons.Controls.Add($BtnRun)

# -------------------------------------------------------------------------
# Progress bar (thin marquee, shown only while running)
# -------------------------------------------------------------------------
$ProgressBar                        = [System.Windows.Forms.ProgressBar]::new()
$ProgressBar.Dock                   = "Top"
$ProgressBar.Height                 = 3
$ProgressBar.Style                  = "Marquee"
$ProgressBar.MarqueeAnimationSpeed  = 25
$ProgressBar.Visible                = $false
$ProgressBar.ForeColor              = $CtpMauve

# -------------------------------------------------------------------------
# Log header row  (label left, Clear Log button right - proximity to log)
# -------------------------------------------------------------------------
$PanelLogHeader           = [System.Windows.Forms.Panel]::new()
$PanelLogHeader.Dock      = "Top"
$PanelLogHeader.Height    = 28
$PanelLogHeader.BackColor = $CtpSurface0

$LblLogHeader             = [System.Windows.Forms.Label]::new()
$LblLogHeader.Text        = "Output"
$LblLogHeader.Font        = $FontSmall
$LblLogHeader.ForeColor   = $CtpSubtext0
$LblLogHeader.AutoSize    = $true
$LblLogHeader.Location    = [System.Drawing.Point]::new(12, 7)

$BtnClear                 = [System.Windows.Forms.Button]::new()
$BtnClear.Text            = "Clear Log"
$BtnClear.Font            = $FontSmall
$BtnClear.BackColor       = $CtpSurface0
$BtnClear.ForeColor       = $CtpText
$BtnClear.FlatStyle       = "Flat"
$BtnClear.FlatAppearance.BorderColor = $CtpSubtext0
$BtnClear.FlatAppearance.BorderSize  = 1
$BtnClear.Height          = 22
$BtnClear.Width           = 80
$BtnClear.Anchor          = "Right,Top"
$BtnClear.Location        = [System.Drawing.Point]::new(700, 3)
$BtnClear.Cursor          = "Hand"
$BtnClear.Enabled         = $false   # disabled until log has content
$BtnClear.Add_Click({ $TxtLog.Clear(); $BtnClear.Enabled = $false })

$PanelLogHeader.Add_Resize({ $BtnClear.Left = $PanelLogHeader.Width - 80 - 8 })
$PanelLogHeader.Controls.AddRange(@($LblLogHeader, $BtnClear))

# -------------------------------------------------------------------------
# Separator
# -------------------------------------------------------------------------
$Sep           = [System.Windows.Forms.Panel]::new()
$Sep.Dock      = "Top"
$Sep.Height    = 1
$Sep.BackColor = $CtpOverlay0

# -------------------------------------------------------------------------
# Log output
# -------------------------------------------------------------------------
$TxtLog             = [System.Windows.Forms.RichTextBox]::new()
$TxtLog.Dock        = "Fill"
$TxtLog.BackColor   = $CtpMantle
$TxtLog.ForeColor   = $CtpText
$TxtLog.Font        = $FontMonoS
$TxtLog.ReadOnly    = $true
$TxtLog.BorderStyle = "None"
$TxtLog.ScrollBars  = "Vertical"
$TxtLog.WordWrap    = $false
$TxtLog.Padding     = [System.Windows.Forms.Padding]::new(8)

# -------------------------------------------------------------------------
# Drag-and-drop: entire Form is a drop target.
# TxtSource also accepts drops directly.
# -------------------------------------------------------------------------
$DropAction = {
    param($s, $e)
    if (-not $e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { return }

    $dropped = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    $valid   = @(
        $dropped | Where-Object {
            (Test-Path $_ -PathType Container) -or
            ((Test-Path $_ -PathType Leaf) -and ($SupportedExts -contains [System.IO.Path]::GetExtension($_).ToLower()))
        }
    )
    $skipped = $dropped.Count - $valid.Count

    if ($valid.Count -gt 0) {
        Update-Selection $valid
        if ($skipped -gt 0) {
            $StatusLabel.Text += "  ($skipped unsupported item(s) ignored)"
        }
    } else {
        $StatusLabel.ForeColor = $CtpYellow
        $StatusLabel.Text      = "No supported archives found in the dropped items."
    }
}
$DragEnterAction = {
    param($s, $e)
    $e.Effect = if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        [System.Windows.Forms.DragDropEffects]::Copy
    } else {
        [System.Windows.Forms.DragDropEffects]::None
    }
}

$Form.Add_DragDrop($DropAction)
$Form.Add_DragEnter($DragEnterAction)
$TxtSource.Add_DragDrop($DropAction)
$TxtSource.Add_DragEnter($DragEnterAction)

# -------------------------------------------------------------------------
# ANSI stripper and log colorizer
# -------------------------------------------------------------------------
$AnsiRx = [System.Text.RegularExpressions.Regex]::new('\x1B\[[0-9;]*m')

function Add-LogLine([string]$raw) {
    $line = $AnsiRx.Replace($raw, "").TrimEnd()
    if (-not $line) { return }

    $color = $CtpText
    if     ($line -match "OK\s+SUCCESS")                     { $color = $CtpGreen  }
    elseif ($line -match "XX\s+FAILED")                      { $color = $CtpRed    }
    elseif ($line -match ">>\s+EXTRACTING")                  { $color = $CtpPeach }
    elseif ($line -match "\*\*\s+OPTIMIZING")                { $color = $CtpSky   }
    elseif ($line -match "##\s+REPACKING")                   { $color = $CtpLavender }
    elseif ($line -match "::\s+SANITIZING")                  { $color = $CtpSubtext0   }
    elseif ($line -match "^=+$")                             { $color = $CtpMauve   }
    elseif ($line -match "Space Reclaimed|Total Reduction")  { $color = $CtpGreen  }
    elseif ($line -match "~~\s+Moving")                      { $color = $CtpYellow }
    elseif ($line -match "BATCH SUMMARY|RUN INITIALIZED")    { $color = $CtpSky   }
    elseif ($line -match "Failed\s*:\s*0")                   { $color = $CtpSubtext0   }
    elseif ($line -match "Failed\s*:\s*[1-9]|XX\s|error")   { $color = $CtpRed    }
    elseif ($line -match "~~\s+INFO")                        { $color = $CtpTeal   }
    elseif ($line -match "!!")                               { $color = $CtpYellow }

    $TxtLog.SelectionStart  = $TxtLog.TextLength
    $TxtLog.SelectionLength = 0
    $TxtLog.SelectionColor  = $color
    $TxtLog.AppendText("$line`n")
    $TxtLog.ScrollToCaret()
}

# -------------------------------------------------------------------------
# Run logic
# -------------------------------------------------------------------------
$script:RunJob          = $null
$script:StartTime       = $null
$script:TempSourceFile  = $null

$BtnRun.Add_Click({
    # $script:SelectedItems is the authoritative list - BtnRun is disabled when it is empty
    if ($script:SelectedItems.Count -eq 0) {
        $StatusLabel.ForeColor = $CtpYellow
        $StatusLabel.Text      = "Select a source folder or archives first."
        return
    }

    # Write all paths to a UTF-8 temp file (one per line).
    # Robust against paths containing commas, quotes, spaces, or unicode -
    # avoids brittle command-line parsing of array values in -File mode.
    $script:TempSourceFile = Join-Path ([System.IO.Path]::GetTempPath()) "ComicDiet_Sources_$([guid]::NewGuid()).txt"
    try {
        $script:SelectedItems | Set-Content -Path $script:TempSourceFile -Encoding utf8 -ErrorAction Stop
    } catch {
        $StatusLabel.ForeColor = $CtpRed
        $StatusLabel.Text      = "Could not write temp source list: $_"
        return
    }

    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.AddRange([string[]]@(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $MainScript,
        "-SourceListFile", $script:TempSourceFile
    ))
    if ($ChkKeepOriginals.Checked) { $argList.Add("-KeepOriginals") }

    $BtnRun.Enabled        = $false
    $BtnRun.Text           = "Optimizing..."
    $BtnClear.Enabled      = $true
    $ProgressBar.Visible   = $true
    $StatusLabel.ForeColor = $CtpSky
    $StatusLabel.Text      = "Optimizing..."
    $StatusTime.Text       = ""
    $script:StartTime      = [datetime]::Now
    $TxtLog.Clear()

    $summary = if ($script:SelectedItems.Count -eq 1) { $script:SelectedItems[0] } else { "$($script:SelectedItems.Count) items" }
    Add-LogLine ">> Starting optimization for: $summary"
    Add-LogLine ""

    $script:RunJob = Start-Job -ScriptBlock {
        param($pwshPath, $argList)
        & $pwshPath @argList 2>&1
    } -ArgumentList (Get-Command pwsh).Source, $argList

    $script:PollTimer          = [System.Windows.Forms.Timer]::new()
    $script:PollTimer.Interval = 250

    $script:PollTimer.Add_Tick({
        if ($null -eq $script:RunJob) {
            $script:PollTimer.Stop()
            $script:PollTimer.Dispose()
            $script:PollTimer = $null
            return
        }

        if ($null -ne $script:StartTime) {
            $e = [datetime]::Now - $script:StartTime
            $StatusTime.Text = "Elapsed: $([math]::Floor($e.TotalMinutes))m$($e.Seconds.ToString('00'))s"
        }

        $lines = Receive-Job -Job $script:RunJob 2>&1
        foreach ($line in $lines) { Add-LogLine "$line" }

        if ($script:RunJob.State -in @("Completed", "Failed", "Stopped")) {
            $script:PollTimer.Stop()
            $script:PollTimer.Dispose()
            $script:PollTimer = $null

            $jobState  = $script:RunJob.State
            $remaining = Receive-Job -Job $script:RunJob 2>&1
            foreach ($line in $remaining) { Add-LogLine "$line" }
            Remove-Job -Job $script:RunJob -Force
            $script:RunJob = $null

            # Clean up temp source list file
            if ($script:TempSourceFile -and (Test-Path $script:TempSourceFile)) {
                Remove-Item $script:TempSourceFile -Force -ErrorAction SilentlyContinue
                $script:TempSourceFile = $null
            }

            $ProgressBar.Visible = $false
            $BtnRun.Enabled      = $true
            $BtnRun.Text         = "Optimize Comics"

            if ($null -ne $script:StartTime) {
                $total = [datetime]::Now - $script:StartTime
                $StatusTime.Text = "Finished in $([math]::Floor($total.TotalMinutes))m$($total.Seconds.ToString('00'))s"
            }

            if ($jobState -eq "Completed") {
                $StatusLabel.ForeColor = $CtpGreen
                $StatusLabel.Text      = "Done."
            } else {
                $StatusLabel.ForeColor = $CtpRed
                $StatusLabel.Text      = "Ended with errors."
            }
        }
    })

    $script:PollTimer.Start()
})

# -------------------------------------------------------------------------
# Assemble form (reverse dock order for correct Top stacking)
# -------------------------------------------------------------------------
$Form.Controls.Add($TxtLog)
$Form.Controls.Add($Sep)
$Form.Controls.Add($PanelLogHeader)
$Form.Controls.Add($ProgressBar)
$Form.Controls.Add($PanelButtons)
$Form.Controls.Add($PanelOpts)
$Form.Controls.Add($PanelFolder)
$Form.Controls.Add($PanelTop)
$Form.Controls.Add($StatusStrip)

# -------------------------------------------------------------------------
# Startup: dependency check
# -------------------------------------------------------------------------
$Form.Add_Shown({
    $missing = @()
    if (-not (Test-Path "C:\Program Files\7-Zip\7z.exe"))       { $missing += "7-Zip"       }
    if (-not (Test-Path (Join-Path $ScriptDir "cjpegli.exe")))  { $missing += "cjpegli.exe" }

    if ($missing.Count -gt 0) {
        Add-LogLine "!! Missing dependencies: $($missing -join ', ')"
        Add-LogLine "   Run Install.bat to set up ComicDiet before using the GUI."
        Add-LogLine ""
        $StatusLabel.ForeColor = $CtpYellow
        $StatusLabel.Text      = "Run Install.bat first"
    } else {
        Add-LogLine ">> Ready. Drag a folder anywhere onto this window, or use Browse."
        Add-LogLine ""
        $StatusLabel.ForeColor = $CtpSubtext0
        $StatusLabel.Text      = "Ready"
    }

    # Pre-populate from -Source parameter (e.g. launched via Explorer context menu)
    if ($Source -and (Test-Path $Source)) {
        Update-Selection @($Source)
        Add-LogLine ">> Source pre-loaded: $Source"
        Add-LogLine ""
    }
})

# -------------------------------------------------------------------------
# Close guard
# -------------------------------------------------------------------------
$Form.Add_FormClosing({
    param($s, $e)
    if ($null -ne $script:RunJob -and $script:RunJob.State -eq "Running") {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Optimization is still running. Close anyway?",
            "ComicDiet",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($r -eq "No") {
            $e.Cancel = $true
        } else {
            Stop-Job  -Job $script:RunJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:RunJob -ErrorAction SilentlyContinue
        }
    }
})

[System.Windows.Forms.Application]::Run($Form)
