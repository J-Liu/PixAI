#!/usr/bin/env python3
"""
Convert U2Net (U-squared Net) saliency detection model to CoreML format.

U2Net is used for salient object detection, which can be applied to:
- Watermark detection
- Portrait segmentation
- Object detection

Requirements:
    pip install torch coremltools numpy

Usage:
    1. Clone U-2-Net repository:
       git clone https://github.com/xuebinqin/U-2-Net.git

    2. Download pretrained model:
       # From U-2-Net repo, download u2net.pth to U-2-Net/saved_models/u2net/

    3. Run conversion:
       python3 convert_u2net_coreml.py --model-path U-2-Net/saved_models/u2net/u2net.pth

Output:
    U2NET.mlpackage - CoreML model package (320x320 input)
"""

import argparse
import os
import sys
import hashlib

import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct
import numpy as np


# ============ U2Net Model Definitions ============

class REBNCONV(nn.Module):
    def __init__(self, in_ch=3, out_ch=3, dirate=1):
        super().__init__()
        self.conv_s1 = nn.Conv2d(in_ch, out_ch, 3, padding=1*dirate, dilation=1*dirate)
        self.bn_s1 = nn.BatchNorm2d(out_ch)
        self.relu_s1 = nn.ReLU(inplace=True)

    def forward(self, x):
        return self.relu_s1(self.bn_s1(self.conv_s1(x)))


class RSU7(nn.Module):
    def __init__(self, in_ch=3, mid_ch=12, out_ch=3):
        super().__init__()
        self.rebnconvin = REBNCONV(in_ch, out_ch, dirate=1)
        self.rebnconv1 = REBNCONV(out_ch, mid_ch, dirate=1)
        self.pool1 = nn.MaxPool2d(2, stride=2)
        self.rebnconv2 = REBNCONV(mid_ch, mid_ch, dirate=1)
        self.pool2 = nn.MaxPool2d(2, stride=2)
        self.rebnconv3 = REBNCONV(mid_ch, mid_ch, dirate=1)
        self.pool3 = nn.MaxPool2d(2, stride=2)
        self.rebnconv4 = REBNCONV(mid_ch, mid_ch, dirate=1)
        self.rebnconv5 = REBNCONV(mid_ch, mid_ch, dirate=2)
        self.rebnconv4d = REBNCONV(mid_ch*2, mid_ch, dirate=1)
        self.rebnconv3d = REBNCONV(mid_ch*2, mid_ch, dirate=1)
        self.rebnconv2d = REBNCONV(mid_ch*2, mid_ch, dirate=1)
        self.rebnconv1d = REBNCONV(mid_ch*2, out_ch, dirate=1)

    def forward(self, x):
        hx = x
        hxin = self.rebnconvin(hx)
        hx1 = self.rebnconv1(hxin)
        hx = self.pool1(hx1)
        hx2 = self.rebnconv2(hx)
        hx = self.pool2(hx2)
        hx3 = self.rebnconv3(hx)
        hx = self.pool3(hx3)
        hx4 = self.rebnconv4(hx)
        hx5 = self.rebnconv5(hx4)
        hx4d = self.rebnconv4d(torch.cat((hx5, hx4), 1))
        hx3d = self.rebnconv3d(torch.cat((F.interpolate(hx4d, scale_factor=2, mode='bilinear', align_corners=True), hx3), 1))
        hx2d = self.rebnconv2d(torch.cat((F.interpolate(hx3d, scale_factor=2, mode='bilinear', align_corners=True), hx2), 1))
        hx1d = self.rebnconv1d(torch.cat((F.interpolate(hx2d, scale_factor=2, mode='bilinear', align_corners=True), hx1), 1))
        return hx1d + hxin


class RSU6(nn.Module):
    def __init__(self, in_ch=3, mid_ch=12, out_ch=3):
        super().__init__()
        self.rebnconvin = REBNCONV(in_ch, out_ch, dirate=1)
        self.rebnconv1 = REBNCONV(out_ch, mid_ch, dirate=1)
        self.pool1 = nn.MaxPool2d(2, stride=2)
        self.rebnconv2 = REBNCONV(mid_ch, mid_ch, dirate=1)
        self.pool2 = nn.MaxPool2d(2, stride=2)
        self.rebnconv3 = REBNCONV(mid_ch, mid_ch, dirate=1)
        self.rebnconv4 = REBNCONV(mid_ch, mid_ch, dirate=2)
        self.rebnconv3d = REBNCONV(mid_ch*2, mid_ch, dirate=1)
        self.rebnconv2d = REBNCONV(mid_ch*2, mid_ch, dirate=1)
        self.rebnconv1d = REBNCONV(mid_ch*2, out_ch, dirate=1)

    def forward(self, x):
        hx = x
        hxin = self.rebnconvin(hx)
        hx1 = self.rebnconv1(hxin)
        hx = self.pool1(hx1)
        hx2 = self.rebnconv2(hx)
        hx = self.pool2(hx2)
        hx3 = self.rebnconv3(hx)
        hx4 = self.rebnconv4(hx3)
        hx3d = self.rebnconv3d(torch.cat((F.interpolate(hx4, scale_factor=2, mode='bilinear', align_corners=True), hx3), 1))
        hx2d = self.rebnconv2d(torch.cat((F.interpolate(hx3d, scale_factor=2, mode='bilinear', align_corners=True), hx2), 1))
        hx1d = self.rebnconv1d(torch.cat((F.interpolate(hx2d, scale_factor=2, mode='bilinear', align_corners=True), hx1), 1))
        return hx1d + hxin


class RSU5(nn.Module):
    def __init__(self, in_ch=3, mid_ch=12, out_ch=3):
        super().__init__()
        self.rebnconvin = REBNCONV(in_ch, out_ch, dirate=1)
        self.rebnconv1 = REBNCONV(out_ch, mid_ch, dirate=1)
        self.pool1 = nn.MaxPool2d(2, stride=2)
        self.rebnconv2 = REBNCONV(mid_ch, mid_ch, dirate=1)
        self.rebnconv3 = REBNCONV(mid_ch, mid_ch, dirate=2)
        self.rebnconv2d = REBNCONV(mid_ch*2, mid_ch, dirate=1)
        self.rebnconv1d = REBNCONV(mid_ch*2, out_ch, dirate=1)

    def forward(self, x):
        hx = x
        hxin = self.rebnconvin(hx)
        hx1 = self.rebnconv1(hxin)
        hx = self.pool1(hx1)
        hx2 = self.rebnconv2(hx)
        hx3 = self.rebnconv3(hx2)
        hx2d = self.rebnconv2d(torch.cat((F.interpolate(hx3, scale_factor=2, mode='bilinear', align_corners=True), hx2), 1))
        hx1d = self.rebnconv1d(torch.cat((F.interpolate(hx2d, scale_factor=2, mode='bilinear', align_corners=True), hx1), 1))
        return hx1d + hxin


class RSU4(nn.Module):
    def __init__(self, in_ch=3, mid_ch=12, out_ch=3):
        super().__init__()
        self.rebnconvin = REBNCONV(in_ch, out_ch, dirate=1)
        self.rebnconv1 = REBNCONV(out_ch, mid_ch, dirate=1)
        self.rebnconv2 = REBNCONV(mid_ch, mid_ch, dirate=2)
        self.rebnconv1d = REBNCONV(mid_ch*2, out_ch, dirate=1)

    def forward(self, x):
        hxin = self.rebnconvin(x)
        hx1 = self.rebnconv1(hxin)
        hx2 = self.rebnconv2(hx1)
        hx1d = self.rebnconv1d(torch.cat((F.interpolate(hx2, scale_factor=2, mode='bilinear', align_corners=True), hx1), 1))
        return hx1d + hxin


class RSU4F(nn.Module):
    def __init__(self, in_ch=3, mid_ch=12, out_ch=3):
        super().__init__()
        self.rebnconvin = REBNCONV(in_ch, out_ch, dirate=1)
        self.rebnconv1 = REBNCONV(out_ch, mid_ch, dirate=1)
        self.rebnconv2 = REBNCONV(mid_ch, mid_ch, dirate=2)
        self.rebnconv3 = REBNCONV(mid_ch, mid_ch, dirate=4)
        self.rebnconv2d = REBNCONV(mid_ch*2, mid_ch, dirate=2)
        self.rebnconv1d = REBNCONV(mid_ch*2, out_ch, dirate=1)

    def forward(self, x):
        hx = x
        hxin = self.rebnconvin(hx)
        hx1 = self.rebnconv1(hxin)
        hx2 = self.rebnconv2(hx1)
        hx3 = self.rebnconv3(hx2)
        hx2d = self.rebnconv2d(torch.cat((hx3, hx2), 1))
        hx1d = self.rebnconv1d(torch.cat((hx2d, hx1), 1))
        return hx1d + hxin


class U2NET(nn.Module):
    """U2Net architecture for salient object detection."""

    def __init__(self, in_ch=3, out_ch=1):
        super().__init__()
        self.stage1 = RSU7(in_ch, 32, 64)
        self.pool12 = nn.MaxPool2d(2, stride=2)
        self.stage2 = RSU6(64, 32, 128)
        self.pool23 = nn.MaxPool2d(2, stride=2)
        self.stage3 = RSU5(128, 64, 256)
        self.pool34 = nn.MaxPool2d(2, stride=2)
        self.stage4 = RSU4(256, 128, 512)
        self.pool45 = nn.MaxPool2d(2, stride=2)
        self.stage5 = RSU4F(512, 256, 512)
        self.pool56 = nn.MaxPool2d(2, stride=2)
        self.stage6 = RSU4F(512, 256, 512)
        self.stage5d = RSU4F(1024, 256, 512)
        self.stage4d = RSU4(1024, 128, 256)
        self.stage3d = RSU5(512, 64, 128)
        self.stage2d = RSU7(256, 32, 64)
        self.stage1d = RSU7(128, 16, 64)
        self.side1 = nn.Conv2d(64, out_ch, 3, padding=1)
        self.side2 = nn.Conv2d(64, out_ch, 3, padding=1)
        self.side3 = nn.Conv2d(128, out_ch, 3, padding=1)
        self.side4 = nn.Conv2d(256, out_ch, 3, padding=1)
        self.side5 = nn.Conv2d(512, out_ch, 3, padding=1)
        self.side6 = nn.Conv2d(512, out_ch, 3, padding=1)

    def forward(self, x):
        hx = x
        hx1 = self.stage1(hx)
        hx2 = self.stage2(self.pool12(hx1))
        hx3 = self.stage3(self.pool23(hx2))
        hx4 = self.stage4(self.pool34(hx3))
        hx5 = self.stage5(self.pool45(hx4))
        hx6 = self.stage6(self.pool56(hx5))

        hx5d = self.stage5d(torch.cat((F.interpolate(hx6, scale_factor=2, mode='bilinear', align_corners=True), hx5), 1))
        hx4d = self.stage4d(torch.cat((F.interpolate(hx5d, scale_factor=2, mode='bilinear', align_corners=True), hx4), 1))
        hx3d = self.stage3d(torch.cat((F.interpolate(hx4d, scale_factor=2, mode='bilinear', align_corners=True), hx3), 1))
        hx2d = self.stage2d(torch.cat((F.interpolate(hx3d, scale_factor=2, mode='bilinear', align_corners=True), hx2), 1))
        hx1d = self.stage1d(torch.cat((F.interpolate(hx2d, scale_factor=2, mode='bilinear', align_corners=True), hx1), 1))

        return (F.sigmoid(self.side1(hx1d)), F.sigmoid(self.side2(hx2d)),
                F.sigmoid(self.side3(hx3d)), F.sigmoid(self.side4(hx4d)),
                F.sigmoid(self.side5(hx5d)), F.sigmoid(self.side6(hx6)))


class U2NetWrapper(nn.Module):
    """Wrapper that returns only the final saliency map (d0 output)."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        outputs = self.model(x)
        return outputs[0]  # Return only the main saliency map


def convert_to_coreml(model_path, output_path, input_size=320):
    """Convert U2Net to CoreML format."""
    print(f"Loading model from: {model_path}")

    # Create model
    model = U2NET(3, 1)

    # Load weights
    state_dict = torch.load(model_path, map_location='cpu', weights_only=False)
    model.load_state_dict(state_dict, strict=True)
    model.eval()

    print("Model loaded successfully!")

    # Test forward pass
    print(f"Testing forward pass with input size {input_size}x{input_size}...")
    dummy = torch.randn(1, 3, input_size, input_size)
    with torch.no_grad():
        outputs = model(dummy)
    print(f"Output shapes: {[o.shape for o in outputs]}")
    print(f"Final output (d0) range: [{outputs[0].min():.4f}, {outputs[0].max():.4f}]")

    # Wrap to return only final saliency map
    wrapped = U2NetWrapper(model)
    wrapped.eval()

    # Test wrapped model
    with torch.no_grad():
        out = wrapped(dummy)
    print(f"Wrapped output shape: {out.shape}")

    # Trace model
    print("Tracing model...")
    traced = torch.jit.trace(wrapped, dummy)

    # Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name='image', shape=(1, 3, input_size, input_size), dtype=np.float32)
        ],
        outputs=[
            ct.TensorType(name='saliency', dtype=np.float32)
        ]
    )

    # Save model
    mlmodel.save(output_path)
    print(f"CoreML model saved to: {output_path}")

    # Calculate SHA256
    model_file = os.path.join(output_path, 'Data', 'com.apple.CoreML', 'model.mlmodel')
    if os.path.exists(model_file):
        with open(model_file, 'rb') as f:
            sha256 = hashlib.sha256(f.read()).hexdigest()
        print(f"SHA256 (model.mlmodel): {sha256}")

    return mlmodel


def test_coreml_model(model_path):
    """Test the converted CoreML model."""
    print("\nTesting CoreML model...")

    model = ct.models.MLModel(model_path)

    # Print model spec
    spec = model.get_spec()
    print("\nModel inputs:")
    for inp in spec.description.input:
        print(f"  {inp.name}")
    print("\nModel outputs:")
    for out in spec.description.output:
        print(f"  {out.name}")

    # Test prediction
    test_input = np.random.rand(1, 3, 320, 320).astype(np.float32)
    output = model.predict({'image': test_input})

    print(f"\nTest output keys: {list(output.keys())}")
    for k, v in output.items():
        if hasattr(v, 'shape'):
            arr = np.array(v)
            print(f"  {k}: shape={v.shape}, range=[{arr.min():.4f}, {arr.max():.4f}]")

    print("\nTest passed!")


def main():
    parser = argparse.ArgumentParser(description='Convert U2Net model to CoreML')
    parser.add_argument('--model-path', default='U-2-Net/saved_models/u2net/u2net.pth',
                        help='Path to U2Net .pth checkpoint')
    parser.add_argument('--output', default='U2NET.mlpackage',
                        help='Output CoreML model path')
    parser.add_argument('--input-size', type=int, default=320,
                        help='Input image size (default: 320)')
    parser.add_argument('--test', action='store_true',
                        help='Test the converted model')

    args = parser.parse_args()

    if not os.path.exists(args.model_path):
        print(f"ERROR: Model not found at {args.model_path}")
        print("\nDownload the model from:")
        print("  https://github.com/xuebinqin/U-2-Net")
        sys.exit(1)

    # Convert to CoreML
    convert_to_coreml(args.model_path, args.output, args.input_size)

    # Test if requested
    if args.test:
        test_coreml_model(args.output)

    print("\nConversion complete!")
    print(f"Output: {args.output}")


if __name__ == '__main__':
    main()
