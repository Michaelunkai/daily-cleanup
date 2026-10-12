# 🧹 Daily-Cleanup

**One PowerShell script that reclaims every byte of junk on your Windows C: drive — safely, every single day.**

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows11&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Safe](https://img.shields.io/badge/Deletable--only-junk%20that%20regenerates-brightgreen)

---

## What it does

`Daily-Cleanup.ps1` deletes **only things that re-download or regenerate automatically** —
shader caches, app-updater leftovers, browser caches, dev package caches, logs, crash dumps,
error reports, the Recycle Bin — and caps restore-point storage so it can never balloon again.

It was battle-tuned on a real gaming + development machine (NVIDIA + AMD GPU, WSL2, Docker,
dozens of dev toolchains, Plex, game launchers) and proved itself in live runs:

```
FREED THIS RUN : 0.70 GB   <- seeded 450 MB of junk, script found it AND
                              250 MB of real accumulation on top
FREED THIS RUN : 20.60 GB  <- first deep clean of a heavily-used machine
```

## The one rule that makes it safe

> **Windows physically refuses to delete a file that a running process holds open.**
> Every deletion in this script goes through `Remove-Item -ErrorAction SilentlyContinue`,
> so in-use files are skipped automatically — a running app can never be broken by it.
> This is proven by the included `mechanic-test.ps1` self-test: free files are deleted,
> an exclusively-locked file survives, every time.

## What it cleans (9 categories, ~70 targets)

| # | Category | Examples |
|---|----------|----------|
| 1 | Temp files | User temp, Windows temp, Squirrel/WinGet temp |
| 2 | GPU & DirectX shader caches | NVIDIA DXCache/GLCache/ComputeCache, AMD DxCache/VkCache/DxcCache, D3DSCache |
| 3 | Updater & installer leftovers | Ollama, LM Studio, Vortex, CurseForge, Paseo, GameSir, NVIDIA driver downloads, Logitech, Edge/Chrome updaters |
| 4 | Browser caches (caches ONLY) | Chrome + all profiles, ChromeAccountProfiles, Edge, Firefox — cache/shader/model folders |
| 5 | Windows system junk | WER reports, Windows Update downloads, Delivery Optimization, minidumps, thumbnails, WDI traces, Windows Sandbox leftovers, SystemTemp |
| 6 | App logs & crash dumps | ZCode, Plex, Tailscale, qBittorrent, Wand, Hydra Launcher, Codex installer temp |
| 7 | Dev package caches | npm, pip, NuGet, Yarn, Gradle, pnpm (prune), Playwright, Codex runtime |
| 8 | Recycle bin + restore-point cap | Empties Recycle Bin; caps shadow storage at 10 GB keeping the newest restore point |
| 9 | (`-Deep`) DISM WinSxS component cleanup | The official supported way to shrink the component store |

## What it NEVER touches

- `C:\Windows\Installer` and `C:\ProgramData\Package Cache` — needed for uninstall/repair
- `C:\Windows\WinSxS` — only DISM touches it, and only with `-Deep`
- `C:\Windows\System32\DriverStore` — installed drivers
- `C:\wsl2` — your WSL Linux data
- `C:\Program Files\WindowsApps` — Store apps
- **All browser profiles, bookmarks, passwords, cookies, history, extensions, Service Worker logins** — only regenerable cache folders
- Plex metadata, search indexes, `Everything.db`, session databases
- Restore points — the newest one is always kept; all are deleted only if you pass `-Shadows`
- **Any installed app, SDK, or game**

Process guards: paths belonging to **Codex** or **Windows Sandbox** are skipped entirely while those apps are running.

## Requirements

- Windows 10 or 11
- Windows PowerShell **5.1** or newer (the built-in one — no installs needed)
- Administrator (the script elevates itself and pauses so you can read the report)

## Install

**Option A — download the script (no build):**

Grab `Daily-Cleanup.ps1` from the [latest release](https://github.com/Michaelunkai/daily-cleanup/releases/latest),
save it anywhere, done.

**Option B — clone:**

```powershell
git clone https://github.com/Michaelunkai/daily-cleanup.git
```

## Usage

```powershell
# Daily run (normal)
powershell -ExecutionPolicy Bypass -File .\Daily-Cleanup.ps1

# Weekly deep clean: adds DISM WinSxS cleanup + Windows Update cache with service stop
powershell -ExecutionPolicy Bypass -File .\Daily-Cleanup.ps1 -Deep

# Also delete ALL restore points (have a real backup solution first!)
powershell -ExecutionPolicy Bypass -File .\Daily-Cleanup.ps1 -Shadows
```

The script self-elevates (UAC prompt), runs through 9 categories, prints a per-item
freed table plus a grand total, and writes a timestamped log to `logs\` next to the script.

### Run it automatically every day at 09:00 (one-time, as admin)

```bat
schtasks /Create /TN "Daily C Cleanup" /SC DAILY /ST 09:00 /RL HIGHEST /TR "powershell -ExecutionPolicy Bypass -NoProfile -File C:\path\to\Daily-Cleanup.ps1"
```

> If a run frees very little, that's the script working: it only finds what
> re-accumulated since the last run. On a clean disk it frees ~0 GB.

## Sample output

```
=====================================================================
        164 MB  User temp
        259 MB  NVIDIA DXCache
        100 MB  DirectX D3DSCache
        100 MB  LM Studio updater cache
         46 MB  ChromeAccountProfiles optimization_guide_model_store
         34 MB  INetCache
         50 MB  WER report queue
  skip     Codex running - .codex tmp kept
        232 MB  Hydra Launcher redist installers
  capped   restore-point storage at 10 GB (newest restore point kept)
---------------------------------------------------------------------
  FREED THIS RUN : 0.70 GB
  Free now       : 1,733.19 GB   (was 1,732.48 GB)
  Elapsed        : 1 s
=====================================================================
```

## Verifying the safety claims yourself

The repo ships with a self-test that proves the core mechanic:

```powershell
powershell -ExecutionPolicy Bypass -File .\mechanic-test.ps1
# -> free files deleted: True / True
# -> locked file survived: True
# -> MECHANIC TEST: PASS
```

## Troubleshooting

| Symptom | Explanation |
|---|---|
| "Freed 0.00 GB" | Disk is already clean. Run again tomorrow, or after app/GPU-driver updates. |
| A UAC prompt appears | Expected — the script self-elevates for `C:\Windows\Temp`, ProgramData, and shadow storage. |
| Some big folder wasn't touched | It's on the protected list (see above) on purpose. |
| Browser feels like first-run after cleaning | Expected once — caches rebuilt as you browse; logins/history are never touched. |

## Build from source

Nothing to build — it's a single PowerShell script. Open it, read every line,
it deletes exactly the paths listed in it and nothing else.

## License

[MIT](LICENSE) © 2026 Michaelunkai
