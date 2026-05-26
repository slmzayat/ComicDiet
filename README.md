# ComicDiet

**ComicDiet** is a PowerShell 7 tool that batch-optimizes comic book archives. It extracts each archive, re-encodes every JPEG image using [Google's Jpegli encoder](https://github.com/libjxl/libjxl), and repacks the result as a `.cbz` file. Archives that don't benefit from re-encoding are handled gracefully - original images are preserved on a per-page basis whenever Jpegli can't produce a smaller result.

Typical savings range from **10% to 75%** depending on how the source was originally encoded.

---

## Features

- Batch-processes entire folder trees or single archives
- Re-encodes JPEGs using Google Jpegli at perceptual quality `-d 1.0` with chroma subsampling 4:4:4
- Per-image size guard: original is kept if Jpegli's output is larger
- PNG support: converts to JPEG unless the image has an alpha channel, which is preserved as-is
- Strips system junk files (`Thumbs.db`, `.DS_Store`, `__MACOSX`, etc.)
- Sanitizes filenames by stripping scene/group tags (e.g. `(Son of Ultron-Empire)`, `(DCP)`)
- Parallel image processing scaled to available RAM and CPU cores
- Output always in `.cbz` (ZIP) format regardless of input format (`.cbr`, `.cbz`, `.cb7`, `.cbt`)
- Moves originals to the Recycle Bin on success (recoverable)
- Dry-run mode to preview output filenames and paths before committing
- [Dracula-themed](https://draculatheme.com) terminal output with WCAG AA contrast

---

## Requirements

| Requirement | Version | Notes |
|---|---|---|
| Windows | 10 or later | Required for winget and Recycle Bin integration |
| PowerShell | 7.4 or later | See installation below |
| 7-Zip | Any recent | Installed automatically by `setup.ps1` |
| cjpegli.exe | Latest libjxl | Downloaded automatically by `setup.ps1` |

---

## Installation

### 1. Install PowerShell 7

Open **Command Prompt** or **Windows PowerShell** and run:

```
winget install --id Microsoft.PowerShell
```

Then close and reopen your terminal so `pwsh` is available on the PATH.

### 2. Get ComicDiet

**Option A - git clone (recommended):**

```
git clone https://github.com/slmzayat/ComicDiet.git
cd ComicDiet
```

**Option B - download ZIP:**

Click **Code > Download ZIP** on this page, then extract the folder anywhere you like (e.g. `C:\Tools\ComicDiet`).

### 3. Run the installer

In **File Explorer**, double-click `Install.bat` inside the ComicDiet folder.

The installer will:

- Set the PowerShell execution policy for your user account
- Unblock the script files if you downloaded a ZIP
- Install 7-Zip via winget if not already present
- Download `cjpegli.exe` from the official libjxl GitHub release and verify its SHA-256 hash
- Optionally add an **"Optimize with ComicDiet"** entry to your folder right-click menu

> The installer requires no administrator privileges.

---

## Usage

### Basic

```powershell
pwsh -File "C:\Path\To\ComicDiet.ps1" -Target "C:\Comics\Unread"
```

### With right-click menu

If you opted in during setup, right-click any folder in File Explorer and select **Optimize with ComicDiet**. Optimized archives are saved to an `Optimized Comics` subfolder inside the target.

### Dry run (preview only)

```powershell
.\ComicDiet.ps1 -Target "C:\Comics\Unread" -DryRun
```

Shows what would be processed and what the output filenames would be. No files are read, written, or deleted.

### Keep originals

```powershell
.\ComicDiet.ps1 -Target "C:\Comics\Unread" -KeepOriginals
```

Skips moving originals to the Recycle Bin. Useful when testing on a new batch.

### Custom binary paths

```powershell
.\ComicDiet.ps1 -Target "C:\Comics" -PathTo7z "D:\Tools\7z.exe" -PathToCjpegli "D:\Tools\cjpegli.exe"
```

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Target` | String | **Required** | Path to a folder (batch) or a single archive file |
| `-PathTo7z` | String | `C:\Program Files\7-Zip\7z.exe` | Path to `7z.exe` |
| `-PathToCjpegli` | String | `.\cjpegli.exe` | Path to `cjpegli.exe` (default: same folder as the script) |
| `-DryRun` | Switch | Off | Preview mode - no files are modified |
| `-KeepOriginals` | Switch | Off | Do not move originals to the Recycle Bin |

---

## How It Works

Each archive goes through four sequential stages. Image optimization within each archive is parallelized across available CPU cores.

```
>> EXTRACTING   Unpacks the archive to a temporary working directory
:: SANITIZING   Removes Thumbs.db, .DS_Store, __MACOSX, and similar junk
** OPTIMIZING   Re-encodes each JPEG/PNG in parallel using Jpegli
## REPACKING    Packs the result into a .cbz (ZIP store) file
```

Concurrency is calculated as `min(RAM_MB / 500, CPU_cores * 0.75)` and scales automatically to the host machine. No manual tuning required.

The output folder is always `Optimized Comics` inside the target directory. Filename collision is handled automatically with a numeric suffix.

---

## Troubleshooting

### "Running scripts is disabled on this system"

This is Windows blocking PowerShell scripts by default. Two ways to fix it:

**Recommended:** Just run `Install.bat` - it handles this automatically.

**Manual fix:** Open PowerShell 7 and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

If you downloaded a ZIP (not a git clone), also run:

```powershell
Unblock-File -Path ".\ComicDiet.ps1"
```

### "winget not found"

winget ships with **App Installer** from the Microsoft Store. If it's missing:

1. Open the Microsoft Store
2. Search for **App Installer**
3. Install or update it
4. Re-run `Install.bat`

### "7-Zip not found" after installation

winget may require a terminal restart before newly installed tools appear on the PATH. Close PowerShell and reopen it, then re-run `Install.bat`.

### Some images weren't re-encoded

Three cases where an original image is intentionally preserved:

1. **Jpegli's output was larger** than the source - the original is kept to avoid size regression
2. **PNG with alpha channel** - converting to JPEG would destroy transparency
3. **Jpegli timed out or crashed** on that specific image - check for error output during the run

---

## Credits

ComicDiet is built on the following open-source projects:

| Project | Author | License | Use |
|---|---|---|---|
| [libjxl / Jpegli](https://github.com/libjxl/libjxl) | JPEG XL Project Authors | BSD 3-Clause | JPEG re-encoding engine |
| [7-Zip](https://7-zip.org) | Igor Pavlov | LGPL 2.1 + unRAR | Archive extraction and repacking |
| [Dracula Theme](https://draculatheme.com) | Zeno Rocha | MIT | Terminal color palette |
| [PowerShell](https://github.com/PowerShell/PowerShell) | Microsoft | MIT | Runtime |

Full license texts are in [`CREDITS.md`](CREDITS.md).

---

## License

ComicDiet is released under the [MIT License](LICENSE).

Copyright (c) 2025 Saleem
