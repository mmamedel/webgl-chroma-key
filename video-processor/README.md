# Video Processor

PyOpenGL-based video processor using the Phase 1 chroma key shader.

## Quick Start

### Option 1: Docker (Recommended for Linux/Production)

```bash
# Build image (run from project root)
cd ..
docker build -f video-processor/Dockerfile -t chroma-key-processor .

# Process video
docker run --rm \
  -v $(pwd)/static:/input:ro \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py \
    -i /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
    -o /output/output.mp4 \
    -b /input/blue.jpg

# Or use the helper script (auto-builds if needed)
cd video-processor
./docker-run.sh \
  -i static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  -o output.mp4 \
  -b static/blue.jpg
```

See **[DOCKER.md](DOCKER.md)** for complete Docker documentation.

### Option 2: Local Python

```bash
# Install dependencies
pip install -r requirements.txt

# Test setup
python test_setup.py

# Process video
python process_video.py \
  -i ../static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  -o ../output.mp4 \
  -b ../static/blue.jpg
```

## Features

- ✅ Uses same GLSL shaders as browser demo
- ✅ GPU-accelerated (OpenGL)
- ✅ Offscreen rendering (headless)
- ✅ Command-line interface
- ✅ Progress tracking
- ✅ Adjustable parameters (transparency, tolerance, key color)
- ✅ Output modes (composite/alpha channel)

## Files

- **`process_video.py`** - Main video processor
- **`test_setup.py`** - Dependency verification script
- **`requirements.txt`** - Python dependencies
- **`PROCESS_VIDEO.md`** - Complete documentation

## Requirements

- Python 3.8+
- OpenGL 3.3+ support
- PyOpenGL, OpenCV, GLFW, NumPy

## Usage

See **[PROCESS_VIDEO.md](PROCESS_VIDEO.md)** for complete documentation including:

- Installation instructions
- All parameters and examples
- Troubleshooting guide
- Performance tips
- SageMaker deployment notes
