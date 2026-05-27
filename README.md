# ComicDiet

Batch-optimizes comic book archives using [Google Jpegli](https://github.com/libjxl/libjxl). Input can be `.cbr`, `.cbz`, `.cb7`, or `.cbt`. Output is always `.cbz`.

---

## Install

**1. Install PowerShell 7** (one-time, if not already installed):
```
winget install --id Microsoft.PowerShell
```

**2. Clone the repo:**
```
git clone https://github.com/slmzayat/ComicDiet.git
```

**3. Double-click `Install.bat`** inside the cloned folder.

Setup installs 7-Zip, downloads `cjpegli.exe` with SHA-256 verification, and optionally adds a right-click context menu entry and a Desktop shortcut.

---

## Use

Double-click **`ComicDiet.bat`**.

Drag a folder or individual archives onto the window, then click **Optimize Comics**. Output goes to an `Optimized Comics` subfolder inside the source.

---

## Why near-lossless?

ComicDiet runs Jpegli with two specific flags:

- **`-d 1.0`** sets the [Butteraugli](https://github.com/google/butteraugli) perceptual distance to 1.0. Below this threshold the difference between original and re-encoded image is below what the human eye can detect under normal viewing conditions.
- **`--chroma_subsampling=444`** disables chroma subsampling entirely. Standard JPEG discards half the color resolution (4:2:0); ComicDiet preserves all of it.

Together these produce smaller files with no visible quality loss. WebP images inside archives are preserved as-is and not re-encoded.

---

## CLI

For scripting and automation, call the engine directly:

```
pwsh -File "scripts\ComicDiet-CLI.ps1" -Source "C:\Comics\Unread"
```

| Flag | Description |
|---|---|
| `-Source` | Folder or individual archive(s). Required. Accepts multiple values. |
| `-DryRun` | Preview output filenames without processing any files. |
| `-KeepOriginals` | Skip moving originals to the Recycle Bin after conversion. |
| `-PathTo7z` | Custom path to `7z.exe`. Default: `C:\Program Files\7-Zip\7z.exe`. |
| `-PathToCjpegli` | Custom path to `cjpegli.exe`. Default: `scripts\cjpegli.exe`. |

---

MIT license. Third-party credits: [docs/CREDITS.md](docs/CREDITS.md).
