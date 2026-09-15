# PixAI

A lightweight, fast, AI-powered image viewer for macOS.

---

## Features

**Small & Fast**
- Native macOS AppKit application — no Electron, no web technologies
- Minimal memory footprint, instant launch
- Smooth image transitions and responsive gestures

**AI-Powered**
- One-click AI auto-enhance (dedup + watermark removal)
- AI super-resolution (Real-ESRGAN)
- AI watermark removal (U2Net)
- Auto AI enhance on image load

**Image Viewing**
- Support for JPEG, PNG, HEIC, HEIF, GIF, WebP, BMP, TIFF
- Zoom, pan, rotate, crop
- Slideshow mode
- Duplicate detection and comparison

**Keyboard-First**
- Full keyboard navigation
- Customizable shortcuts
- Quick actions at your fingertips

---

## Download

Download from GitHub Releases:

[https://github.com/J-Liu/PixAI/releases](https://github.com/J-Liu/PixAI/releases)

### Bypassing Gatekeeper

Since PixAI is not notarized by Apple, you need to bypass the security check to run it.

**Method 1: Command Line**
```bash
xattr -cr /path/to/PixAI.app
```

**Method 2: System Preferences**
1. Right-click `PixAI.app` and select "Open"
2. Click "Open" in the security dialog
3. Or go to System Preferences → Privacy & Security → click "Open Anyway"

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

---

## AI Models

PixAI uses local AI models that run entirely on your Mac — no cloud, no internet required for inference.

Models are downloaded on first use (or on startup if enabled in Preferences):

- **Real-ESRGAN** — AI super-resolution for upscaling images
- **U2Net** — AI watermark detection and removal

---

## Configuration

Settings are stored in `~/.pixai/config.json`.

Open Preferences with `Cmd+,` to configure:

- General: language, transition animations
- Slideshow: interval timing
- AI: auto-enhance options, one-click mode
- Advanced: proxy settings, image cache, logging

---

## Internationalization

PixAI supports:

- English
- 简体中文 (Simplified Chinese)
- 繁體中文 (Traditional Chinese)

Change language in Preferences → General.

---

## Development

Built with Swift and AppKit.

### Prerequisites

- CMake 3.20+
- Python 3.8+
- Xcode Command Line Tools

Install with Homebrew:
```bash
brew install cmake python3
xcode-select --install
```

### Build from Source

1. Clone the repository:
```bash
git clone https://github.com/J-Liu/PixAI.git
cd PixAI
```

2. Build (one command):
```bash
./build.sh
```

The script will automatically download and build ExecuTorch xcframeworks from the **v0.6.0 release** if not present (15-30 min on first run).

Subsequent builds are fast (seconds) — the xcframeworks are cached in `Vendor/ExecuTorch/`.

### Build Prerequisites

- CMake 3.20+
- Python 3.10+
- Xcode Command Line Tools

Install with Homebrew:
```bash
brew install cmake python@3.11
xcode-select --install
```

### Clean Build Artifacts

After building, you can remove the ExecuTorch build directory (~2GB):
```bash
rm -rf .executorch_build
```

The xcframeworks in `Vendor/ExecuTorch/` are required for future builds.

### Dependencies

**ExecuTorch xcframeworks** (for U2Net watermark detection model):

| File | Description |
|------|-------------|
| `executorch.xcframework` | Core ExecuTorch runtime |
| `backend_coreml.xcframework` | CoreML backend for Apple Silicon |
| `kernels_optimized.xcframework` | Optimized operators |
| `threadpool.xcframework` | Thread pool for parallel execution |

**Source**: [ExecuTorch](https://github.com/pytorch/executorch) v0.6.0 release (Apache 2.0 License)

Built automatically by `./build.sh` on first run.

---

## License

GNU Affero General Public License v3.0 (AGPL-3.0)

---

## Acknowledgments

- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) for super-resolution
- [U2Net](https://github.com/xuebinqin/U-2-Net) for salient object detection

---

Made with ❤️ for my daily use. Hope you like it.