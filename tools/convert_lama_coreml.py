#!/usr/bin/env python3
"""
Convert LaMa (Large Mask Inpainting) model to CoreML format.

Requirements:
    pip install torch coremltools pyyaml

Usage:
    1. Clone LaMa repository:
       git clone https://github.com/advimman/lama.git
       cd lama

    2. Download big-lama checkpoint:
       # See LaMa repo for download instructions

    3. Run conversion:
       python3 convert_lama_coreml.py --config big-lama/config.yaml --checkpoint big-lama/models/best.ckpt

Output:
    LaMa.mlpackage - CoreML model package
"""

import argparse
import os
import sys
import hashlib

import torch
import torch.nn.functional as F
import coremltools as ct
import numpy as np
import yaml


def resolve_value(val, full_config):
    """Resolve config value references like ${path.to.value}."""
    if isinstance(val, str) and val.startswith('${'):
        path = val[2:-1].split('.')
        result = full_config
        for key in path:
            if key in result:
                result = result[key]
            else:
                return val
        return result
    return val


def load_lama_generator(config_path, checkpoint_path):
    """Load LaMa generator model from config and checkpoint."""
    # Import LaMa modules
    if not os.path.exists('lama'):
        print("ERROR: LaMa repository not found. Clone it first:")
        print("  git clone https://github.com/advimman/lama.git")
        sys.exit(1)

    sys.path.insert(0, 'lama')
    from saicinpainting.training.modules import make_generator

    print(f"Loading config from: {config_path}")
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    print("Creating generator model...")
    gen_config = config['generator']

    # Resolve config references
    init_conv = gen_config.get('init_conv_kwargs', {})
    downsample_conv = gen_config.get('downsample_conv_kwargs', {})
    resnet_conv = gen_config.get('resnet_conv_kwargs', {})

    init_conv['ratio_gin'] = resolve_value(init_conv.get('ratio_gin', 0), config)
    init_conv['ratio_gout'] = resolve_value(init_conv.get('ratio_gout', 0), config)
    downsample_conv['ratio_gin'] = resolve_value(downsample_conv.get('ratio_gin', init_conv.get('ratio_gout', 0)), config)
    downsample_conv['ratio_gout'] = resolve_value(downsample_conv.get('ratio_gout', downsample_conv.get('ratio_gin', 0)), config)
    resnet_conv['ratio_gin'] = resolve_value(resnet_conv.get('ratio_gin', 0.75), config)
    resnet_conv['ratio_gout'] = resolve_value(resnet_conv.get('ratio_gout', resnet_conv.get('ratio_gin', 0.75)), config)

    gen_params = {
        'input_nc': gen_config.get('input_nc', 4),
        'output_nc': gen_config.get('output_nc', 3),
        'ngf': gen_config.get('ngf', 64),
        'n_downsampling': gen_config.get('n_downsampling', 3),
        'n_blocks': gen_config.get('n_blocks', 18),
        'add_out_act': gen_config.get('add_out_act', 'sigmoid'),
        'init_conv_kwargs': init_conv,
        'downsample_conv_kwargs': downsample_conv,
        'resnet_conv_kwargs': resnet_conv,
    }

    generator = make_generator(config, gen_config['kind'], **gen_params)

    print(f"Loading checkpoint from: {checkpoint_path}")
    checkpoint = torch.load(checkpoint_path, map_location='cpu', weights_only=False)
    state_dict = checkpoint.get('state_dict', checkpoint)

    # Extract generator state
    gen_state = {k.replace('generator.', ''): v for k, v in state_dict.items() if k.startswith('generator.')}
    if not gen_state:
        gen_state = state_dict

    generator.load_state_dict(gen_state, strict=False)
    generator.eval()

    print("Model loaded successfully!")
    return generator


def convert_to_coreml(generator, output_path, input_size=256):
    """Convert LaMa generator to CoreML format."""
    print(f"Converting to CoreML with input size {input_size}x{input_size}...")

    # Create dummy inputs
    # LaMa expects image (3 channels) and mask (1 channel) as separate inputs
    image_input = torch.randn(1, 3, input_size, input_size)
    mask_input = torch.randn(1, 1, input_size, input_size)

    # Test forward pass
    with torch.no_grad():
        output = generator(image_input, mask_input)
    print(f"Output shape: {output.shape}")
    print(f"Output range: [{output.min():.4f}, {output.max():.4f}]")

    # Trace the model
    print("Tracing model...")
    traced = torch.jit.trace(generator, (image_input, mask_input))

    # Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name='image', shape=(1, 3, input_size, input_size), dtype=np.float32),
            ct.TensorType(name='mask', shape=(1, 1, input_size, input_size), dtype=np.float32)
        ],
        outputs=[
            ct.TensorType(name='output', dtype=np.float32)
        ]
    )

    # Save model
    mlmodel.save(output_path)
    print(f"CoreML model saved to: {output_path}")

    # Calculate SHA256
    if output_path.endswith('.mlpackage'):
        # For mlpackage, we need to hash the model.mlmodel file inside
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
    test_image = np.random.rand(1, 3, 256, 256).astype(np.float32)
    test_mask = np.random.rand(1, 1, 256, 256).astype(np.float32)

    output = model.predict({'image': test_image, 'mask': test_mask})
    print(f"\nTest output keys: {list(output.keys())}")
    for k, v in output.items():
        if hasattr(v, 'shape'):
            arr = np.array(v)
            print(f"  {k}: shape={v.shape}, range=[{arr.min():.4f}, {arr.max():.4f}]")

    print("\nTest passed!")


def main():
    parser = argparse.ArgumentParser(description='Convert LaMa model to CoreML')
    parser.add_argument('--config', default='big-lama/config.yaml',
                        help='Path to LaMa config.yaml')
    parser.add_argument('--checkpoint', default='big-lama/models/best.ckpt',
                        help='Path to LaMa checkpoint')
    parser.add_argument('--output', default='LaMa.mlpackage',
                        help='Output CoreML model path')
    parser.add_argument('--input-size', type=int, default=256,
                        help='Input image size (default: 256)')
    parser.add_argument('--test', action='store_true',
                        help='Test the converted model')

    args = parser.parse_args()

    # Load model
    generator = load_lama_generator(args.config, args.checkpoint)

    # Convert to CoreML
    convert_to_coreml(generator, args.output, args.input_size)

    # Test if requested
    if args.test:
        test_coreml_model(args.output)

    print("\nConversion complete!")
    print(f"Output: {args.output}")


if __name__ == '__main__':
    main()
