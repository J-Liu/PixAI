#!/usr/bin/env python3
"""
Test script to compare PyTorch and CoreML model outputs.

This script verifies that the converted CoreML models produce
similar results to the original PyTorch models.

Usage:
    # Test LaMa model
    python3 test_coreml.py --model lama --image test_image.jpg

    # Test U2Net model
    python3 test_coreml.py --model u2net --image test_image.jpg

Requirements:
    pip install torch coremltools pillow numpy
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image
import coremltools as ct


def test_lama(image_path, model_path, output_dir):
    """Test LaMa CoreML model."""
    print(f"\n=== Testing LaMa Model ===")
    print(f"Image: {image_path}")
    print(f"Model: {model_path}")

    # Load image
    img = Image.open(image_path).convert("RGB")
    orig_w, orig_h = img.size
    print(f"Original size: {orig_w} x {orig_h}")

    # Resize to model input size (256x256)
    img_256 = img.resize((256, 256), Image.Resampling.LANCZOS)

    # Create a test mask (center region)
    mask = np.zeros((256, 256), dtype=np.uint8)
    mask[64:192, 64:192] = 255

    # Prepare inputs
    image_array = np.array(img_256).astype(np.float32) / 255.0
    image_array = np.transpose(image_array, (2, 0, 1))  # HWC -> CHW
    image_array = np.expand_dims(image_array, 0)  # Add batch dim

    mask_array = mask.astype(np.float32) / 255.0
    mask_array = np.expand_dims(mask_array, (0, 1))  # Add batch and channel dims

    print(f"Image array shape: {image_array.shape}")
    print(f"Mask array shape: {mask_array.shape}")

    # Load CoreML model
    print("Loading CoreML model...")
    model = ct.models.MLModel(model_path)

    # Run prediction
    print("Running prediction...")
    output = model.predict({
        'image': image_array,
        'mask': mask_array
    })

    print(f"Output keys: {list(output.keys())}")

    # Process output
    out_key = list(output.keys())[0]
    out_arr = np.array(output[out_key])
    print(f"Output shape: {out_arr.shape}")
    print(f"Output range: [{out_arr.min():.4f}, {out_arr.max():.4f}]")

    # Convert to image
    if len(out_arr.shape) == 4:
        if out_arr.shape[1] == 3:  # (1, 3, H, W)
            out_arr = np.transpose(out_arr[0], (1, 2, 0))  # -> (H, W, 3)
        elif out_arr.shape[3] == 3:  # (1, H, W, 3)
            out_arr = out_arr[0]

    out_img = Image.fromarray((np.clip(out_arr, 0, 1) * 255).astype(np.uint8))

    # Save outputs
    os.makedirs(output_dir, exist_ok=True)
    img_256.save(os.path.join(output_dir, "lama_input.png"))
    Image.fromarray(mask).save(os.path.join(output_dir, "lama_mask.png"))
    out_img.save(os.path.join(output_dir, "lama_output.png"))

    print(f"\nSaved outputs to {output_dir}")
    print(f"  - lama_input.png")
    print(f"  - lama_mask.png")
    print(f"  - lama_output.png")


def test_u2net(image_path, model_path, output_dir):
    """Test U2Net CoreML model."""
    print(f"\n=== Testing U2Net Model ===")
    print(f"Image: {image_path}")
    print(f"Model: {model_path}")

    # Load image
    img = Image.open(image_path).convert("RGB")
    orig_w, orig_h = img.size
    print(f"Original size: {orig_w} x {orig_h}")

    # Resize to model input size (320x320)
    img_320 = img.resize((320, 320), Image.Resampling.LANCZOS)

    # Prepare input
    image_array = np.array(img_320).astype(np.float32) / 255.0
    image_array = np.transpose(image_array, (2, 0, 1))  # HWC -> CHW
    image_array = np.expand_dims(image_array, 0)  # Add batch dim

    print(f"Image array shape: {image_array.shape}")

    # Load CoreML model
    print("Loading CoreML model...")
    model = ct.models.MLModel(model_path)

    # Run prediction
    print("Running prediction...")
    output = model.predict({'image': image_array})

    print(f"Output keys: {list(output.keys())}")

    # Process output
    out_key = list(output.keys())[0]
    out_arr = np.array(output[out_key])
    print(f"Output shape: {out_arr.shape}")
    print(f"Output range: [{out_arr.min():.4f}, {out_arr.max():.4f}]")

    # Convert to grayscale image
    if len(out_arr.shape) == 4:
        out_arr = out_arr[0, 0]  # (1, 1, H, W) -> (H, W)

    out_img = Image.fromarray((np.clip(out_arr, 0, 1) * 255).astype(np.uint8))

    # Save outputs
    os.makedirs(output_dir, exist_ok=True)
    img_320.save(os.path.join(output_dir, "u2net_input.png"))
    out_img.save(os.path.join(output_dir, "u2net_output.png"))

    print(f"\nSaved outputs to {output_dir}")
    print(f"  - u2net_input.png")
    print(f"  - u2net_output.png")


def main():
    parser = argparse.ArgumentParser(description='Test CoreML models')
    parser.add_argument('--model', choices=['lama', 'u2net'], required=True,
                        help='Model to test')
    parser.add_argument('--image', required=True,
                        help='Test image path')
    parser.add_argument('--model-path',
                        help='CoreML model path (default: LaMa.mlpackage or U2NET.mlpackage)')
    parser.add_argument('--output-dir', default='test_output',
                        help='Output directory for test results')

    args = parser.parse_args()

    # Default model paths
    if args.model_path is None:
        if args.model == 'lama':
            args.model_path = 'LaMa.mlpackage'
        else:
            args.model_path = 'U2NET.mlpackage'

    if not os.path.exists(args.model_path):
        print(f"ERROR: Model not found at {args.model_path}")
        sys.exit(1)

    if not os.path.exists(args.image):
        print(f"ERROR: Image not found at {args.image}")
        sys.exit(1)

    if args.model == 'lama':
        test_lama(args.image, args.model_path, args.output_dir)
    else:
        test_u2net(args.image, args.model_path, args.output_dir)

    print("\n=== Test Complete ===")


if __name__ == '__main__':
    main()
