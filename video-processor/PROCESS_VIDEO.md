# Video Processing with PyOpenGL

Process videos using the Phase 1 chroma key shader outside the browser.

## Installation

```bash
# Navigate to video-processor directory
cd video-processor

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## Usage

All commands should be run from the `video-processor` directory.

### Basic Usage (Default Settings)

```bash
python process_video.py \
  --input ../static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  --output ../output.mp4 \
  --background ../static/blue.jpg
```

### Custom Parameters

```bash
python process_video.py \
  --input ../static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  --output ../output.mp4 \
  --background ../static/blue.jpg \
  --transparency 60.0 \
  --tolerance 45.0 \
  --key-color 0.157 0.576 0.129
```

### Alpha Channel Output (Matte Only)

```bash
python process_video.py \
  --input ../static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  --output ../matte.mp4 \
  --background ../static/blue.jpg \
  --output-mode 1
```

## Parameters

| Parameter        | Short | Description          | Default           | Range    |
| ---------------- | ----- | -------------------- | ----------------- | -------- |
| `--input`        | `-i`  | Input video file     | Required          | -        |
| `--output`       | `-o`  | Output video file    | Required          | -        |
| `--background`   | `-b`  | Background image     | Required          | -        |
| `--transparency` | `-t`  | Keying threshold     | 50.0              | 0-100    |
| `--tolerance`    |       | Color range          | 50.0              | 0-100    |
| `--key-color`    |       | RGB key color        | 0.157 0.576 0.129 | 0-1 each |
| `--output-mode`  |       | 0=Composite, 1=Alpha | 0                 | 0 or 1   |

## Examples

### Aggressive Keying

```bash
python process_video.py -i ../static/input.mp4 -o ../output.mp4 -b ../static/blue.jpg \
  --transparency 70 --tolerance 60
```

### Conservative Keying

```bash
python process_video.py -i ../static/input.mp4 -o ../output.mp4 -b ../static/blue.jpg \
  --transparency 40 --tolerance 40
```

### Blue Screen

```bash
python process_video.py -i ../static/input.mp4 -o ../output.mp4 -b ../static/blue.jpg \
  --key-color 0.0 0.0 1.0
```

### Generate Matte for Inspection

```bash
python process_video.py -i ../static/input.mp4 -o ../matte.mp4 -b ../static/blue.jpg \
  --output-mode 1
```

## Performance

- Processes at ~30-60 fps on most systems
- GPU accelerated (uses OpenGL)
- Progress updates every 30 frames
- Output is H.264 MP4 (mp4v codec)

## Troubleshooting

### "Failed to initialize GLFW"

- Ensure you have OpenGL support on your system
- On Linux: `sudo apt-get install libglfw3 libglfw3-dev`
- On macOS: Should work out of the box
- On Windows: Install Visual C++ redistributables

### "Failed to load background"

- Check that the background image path is correct
- Supported formats: JPG, PNG, BMP, etc.

### Shader compilation errors

- Ensure shader files are in `src/lib/shaders/`
- Check that `basic.vert` and `phase1.frag` exist

### Slow processing

- Install `PyOpenGL-accelerate` for better performance
- Use lower resolution input videos for testing
- Consider using a faster codec for output

## Output Format

- Codec: H.264 (mp4v)
- Container: MP4
- Same resolution and FPS as input
- RGB color space (no alpha in file, transparency applied)

## Notes

- Uses the same GLSL shaders as the browser version
- Parameters match exactly with Phase 1 web UI
- Background image is resized to match video dimensions
- Offscreen rendering (no window displayed)

## Next Steps

To use in production (e.g., SageMaker):

1. Replace `mp4v` codec with `avc1` or `x264` for better compatibility
2. Add batch processing for multiple files
3. Add S3 integration for cloud storage
4. Consider GPU instance for faster processing
