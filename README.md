# ComicDiet

**ComicDiet** is a PowerShell 7 batch optimizer for comic book archives. It re-encodes every JPEG using [Google's Jpegli encoder](https://github.com/libjxl/libjxl) and repacks the result as a `.cbz` file. Originals are moved to the Recycle Bin after a successful conversion.

Typical savings: **10% to 75%** depending on how the source was originally encoded.

---

## How It Works

Each archive goes through four stages. Image encoding within each archive is parallelized across all available CPU cores.

```
>> EXTRACTING   Unpacks the archive to a temporary folder
:: SANITIZING   Removes Thumbs.db, .DS_Store, __MACOSX, and similar junk
** OPTIMIZING   Re-encodes each image in parallel using Jpegli
## REPACKING    Packs the result into a .cbz (ZIP) file
```

- Accepts `.cbr`, `.cbz`, `.cb7`, `.cbt` - output is always `.cbz`
- Per-image size guard: original page is kept if Jpegli's output is larger
- PNGs with alpha channels are preserved as-is (transparency safe)
- Concurrency scales automatically to your machine - no tuning needed

---

## Installation

### Step 1 - Install PowerShell 7

Open **Command Prompt** and run:

```
winget install --id Microsoft.PowerShell
```

Close and reopen your terminal when done.

### Step 2 - Download ComicDiet

**Option A - git clone:**
```
git clone https://github.com/slmzayat/ComicDiet.git
```

**Option B - download ZIP:**

Click **Code > Download ZIP** on this page, then extract the folder anywhere (e.g. `C:\Tools\ComicDiet`).

### Step 3 - Run the installer

Double-click `Install.bat` inside the ComicDiet folder.

It will automatically:
- Fix the PowerShell execution policy for your user account
- Install 7-Zip if not already present
- Download `cjpegli.exe` from the official libjxl release and verify its SHA-256
- Optionally add **"Optimize with ComicDiet"** to your folder right-click menu

No administrator privileges required.

---

## Usage

### Right-click a folder (if you opted in during setup)

Right-click any folder > **Optimize with ComicDiet**. Results go into an `Optimized Comics` subfolder.

### Command line

```powershell
.\ComicDiet.ps1 -Target "C:\Comics\Unread"
```

### Preview before committing

```powershell
.\ComicDiet.ps1 -Target "C:\Comics\Unread" -DryRun
```

### Keep originals

```powershell
.\ComicDiet.ps1 -Target "C:\Comics\Unread" -KeepOriginals
```

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Target` | Required | Folder (batch) or single archive file |
| `-DryRun` | Off | Preview mode - nothing is modified |
| `-KeepOriginals` | Off | Skip moving originals to Recycle Bin |
| `-PathTo7z` | `C:\Program Files\7-Zip\7z.exe` | Custom path to `7z.exe` |
| `-PathToCjpegli` | `.\cjpegli.exe` | Custom path to `cjpegli.exe` |

---

## Troubleshooting

**"Running scripts is disabled on this system"**
Run `Install.bat` - it fixes this automatically. Or manually:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
If you downloaded a ZIP, also run:
```powershell
Unblock-File -Path ".\ComicDiet.ps1"
```

**"winget not found"**
Open the Microsoft Store, search for **App Installer**, install or update it, then re-run `Install.bat`.

**Some images weren't re-encoded**
This is intentional in two cases: Jpegli's output was larger than the source (original kept), or the PNG had an alpha channel (transparency preserved).

---

## Credits

| Project | Author | License |
|---|---|---|
| [libjxl / Jpegli](https://github.com/libjxl/libjxl) | JPEG XL Project Authors | BSD 3-Clause |
| [7-Zip](https://7-zip.org) | Igor Pavlov | LGPL 2.1 |
| [Dracula Theme](https://draculatheme.com) | Zeno Rocha | MIT |
| [PowerShell](https://github.com/PowerShell/PowerShell) | Microsoft | MIT |

Full license texts in [`CREDITS.md`](CREDITS.md).

---

## License

MIT - see [LICENSE](LICENSE).

Copyright (c) 2025 Saleem
