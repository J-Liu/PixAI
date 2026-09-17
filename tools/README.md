# Model Conversion Tools

Scripts for converting PyTorch models to CoreML format for PixAI.

## Prerequisites

### Python Version

**Python 3.10 - 3.11** recommended.

Python 3.12+ may have compatibility issues with some packages.

### Required Packages

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install from requirements.txt
pip install -r requirements.txt
```

Or install specific versions manually:

```bash
pip install torch==2.1.0
pip install coremltools==7.1
pip install pillow==10.1.0
pip install numpy==1.26.0
pip install pyyaml==6.0.1
pip install onnx==1.15.0  # Optional, for ONNX export
```

### Platform Requirements

- **macOS**: Required for CoreML conversion (coremltools only works on macOS)
- **Architecture**: Intel (x86_64) or Apple Silicon (arm64)
- **Xcode**: Xcode 15+ with Command Line Tools installed

### Verify Installation

```bash
python3 -c "import torch; print(f'PyTorch: {torch.__version__}')"
python3 -c "import coremltools; print(f'coremltools: {coremltools.__version__}')"
```

## U2Net (Saliency Detection)

Used for watermark detection in PixAI.

### 1. Clone U-2-Net

```bash
git clone https://github.com/xuebinqin/U-2-Net.git
```

### 2. Download Pretrained Model

Download `u2net.pth` from the U-2-Net repository and place it at:
`U-2-Net/saved_models/u2net/u2net.pth`

### 3. Convert

```bash
python3 convert_u2net_coreml.py \
    --model-path U-2-Net/saved_models/u2net/u2net.pth \
    --output U2NET.mlpackage \
    --test
```

### Output

- `U2NET.mlpackage` - CoreML model package
- Input: 320×320 RGB image (normalized 0-1)
- Output: 320×320 saliency map (0-1)

## LaMa (Image Inpainting)

Used for watermark removal in PixAI.

### 1. Clone LaMa

```bash
git clone https://github.com/advimman/lama.git
```

### 2. Download Checkpoint

Download `big-lama` checkpoint and place it at:
- `big-lama/config.yaml`
- `big-lama/models/best.ckpt`

See the LaMa repository for download instructions.

### 3. Convert

```bash
python3 convert_lama_coreml.py \
    --config big-lama/config.yaml \
    --checkpoint big-lama/models/best.ckpt \
    --output LaMa.mlpackage \
    --test
```

### Output

- `LaMa.mlpackage` - CoreML model package
- Inputs:
  - `image`: 256×256 RGB image (normalized 0-1)
  - `mask`: 256×256 grayscale mask (normalized 0-1)
- Output: 256×256 RGB image (inpainting result)

## Testing

Test the converted models:

```bash
# Test U2Net
python3 test_coreml.py --model u2net --image test.jpg --output-dir test_output

# Test LaMa
python3 test_coreml.py --model lama --image test.jpg --output-dir test_output
```

## Packaging for Distribution

After conversion, package the `.mlpackage` for distribution:

```bash
# Create zip archives
zip -r U2Net-CoreML.zip U2NET.mlpackage
zip -r big-lama-coreml.zip LaMa.mlpackage

# Calculate SHA256 for verification
openssl sha256 U2Net-CoreML.zip
openssl sha256 big-lama-coreml.zip
```

Update the SHA256 values in `Sources/AI/ModelPlugin.swift`.

## Model Specifications

### U2Net

- **Architecture**: U2Net (U-squared Net)
- **Input Size**: 320×320×3 (RGB)
- **Output Size**: 320×320×1 (saliency map)
- **Purpose**: Detect salient regions (watermarks)
- **File Size**: ~84 MB

### LaMa

- **Architecture**: LaMa (Large Mask Inpainting)
- **Input Size**: 256×256 (image + mask)
- **Output Size**: 256×256×3 (RGB)
- **Purpose**: Inpaint masked regions
- **File Size**: ~196 MB

## Troubleshooting

### "Model not found" error

Ensure you've downloaded the pretrained weights to the correct paths.

### "Module not found" error

Install missing dependencies:
```bash
pip install <module_name>
```

### Different input sizes

You can change the input size with `--input-size`:
```bash
python3 convert_lama_coreml.py --input-size 512 ...
```

Note: Larger sizes require more memory and may be slower.

## License

The conversion scripts are provided under AGPL-3.0-or-later.

The original models have their own licenses:
- U2Net: Apache 2.0
- LaMa: See the LaMa repository for license details
