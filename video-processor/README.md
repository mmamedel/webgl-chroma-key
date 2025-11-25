# Video Processor

PyOpenGL-based video processor using the Phase 4 chroma key shader with ProRes 4444 alpha channel support.

---

## Table of Contents

- [Quick Start](#quick-start)
  - [Docker (Recommended)](#docker-recommended)
  - [Local Python](#local-python)
- [Features](#features)
- [CLI Parameters](#cli-parameters)
- [Examples](#examples)
- [Performance](#performance)
- [Docker Details](#docker-details)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

---

## Quick Start

### Docker (Recommended)

**Build the image** (run from project root):

```bash
cd /path/to/chroma-key
docker build -f video-processor/Dockerfile -t chroma-key-processor .
```

**Process a video**:

```bash
docker run --rm \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py \
    -i /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
    -o /output/output.mov \
    --transparency 50 \
    --tolerance 56.8 \
    --highlight 50 \
    --shadow 50 \
    --pedestal 0 \
    --spill-suppression 30
```

**With custom parameters**:

```bash
docker run --rm \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py \
    -i /input/video.mp4 \
    -o /output/output.mov \
    --transparency 60 \
    --tolerance 45
```

**Keep PNG frames for inspection**:

```bash
docker run --rm \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py \
    -i /input/video.mp4 \
    -o /output/output.mov \
    --keep-frames
```

### Local Python

**Install dependencies**:

```bash
cd video-processor

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Test setup
python test_setup.py
```

**Process a video**:

```bash
python process_video.py \
  -i ../static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  -o ../output.mov \
  --transparency 50 \
  --tolerance 56.8
```

---

## Features

- ✅ **Phase 4 Ultra Key** GLSL shader (same as browser demo)
- ✅ **GPU-accelerated** (OpenGL)
- ✅ **Offscreen rendering** (headless)
- ✅ **ProRes 4444 output** with alpha channel
- ✅ **Command-line interface**
- ✅ **Performance tracking** and metrics
- ✅ **Adjustable parameters** (transparency, tolerance, highlight, shadow, pedestal, spill suppression)
- ✅ **Output modes** (composite/alpha channel/status)
- ✅ **PNG frame preservation** for inspection

---

## CLI Parameters

| Parameter             | Short | Description                          | Default           | Range    |
| --------------------- | ----- | ------------------------------------ | ----------------- | -------- |
| `--input`             | `-i`  | Input video file                     | Required          | -        |
| `--output`            | `-o`  | Output video file (.mov for ProRes)  | Required          | -        |
| `--transparency`      | `-t`  | Keying threshold                     | 50.0              | 0-100    |
| `--tolerance`         |       | Color range                          | 50.0              | 0-100    |
| `--highlight`         |       | Bright area transparency             | 50.0              | 0-100    |
| `--shadow`            |       | Dark area transparency               | 50.0              | 0-100    |
| `--pedestal`          |       | Shifts entire alpha range            | 0.0               | 0-100    |
| `--spill-suppression` |       | Removes color spill                  | 30.0              | 0-100    |
| `--key-color`         |       | RGB key color                        | 0.157 0.576 0.129 | 0-1 each |
| `--output-mode`       |       | 0=Composite+Alpha, 1=Alpha, 2=Status | 0                 | 0-2      |
| `--keep-frames`       |       | Preserve PNG frames for inspection   | False             | flag     |

**Full example**:

```bash
python process_video.py \
  -i input.mp4 \
  -o output.mov \
  --transparency 50 \
  --tolerance 56.8 \
  --highlight 50 \
  --shadow 50 \
  --pedestal 0 \
  --spill-suppression 30 \
  --key-color 0.157 0.576 0.129 \
  --output-mode 0 \
  --keep-frames
```

---

## Examples

### Aggressive Keying

```bash
python process_video.py -i input.mp4 -o output.mov \
  --transparency 70 --tolerance 60
```

### Conservative Keying

```bash
python process_video.py -i input.mp4 -o output.mov \
  --transparency 40 --tolerance 40
```

### Blue Screen Keying

```bash
python process_video.py -i input.mp4 -o output.mov \
  --key-color 0.0 0.0 1.0
```

### Generate Alpha Matte Only

```bash
python process_video.py -i input.mp4 -o matte.mov \
  --output-mode 1
```

### Generate Status Visualization

```bash
python process_video.py -i input.mp4 -o status.mov \
  --output-mode 2
```

---

## Performance

### Expected Speed

- **Processing speed**: ~19-22 FPS for 1920x1080 video
- **Docker**: ~15-20 FPS (software rendering via Mesa)
- **Local with GPU**: ~22-25 FPS

### Performance Breakdown

For a 1209-frame, ~40s video (1920x1080):

| Stage            | Time    | Percentage |
| ---------------- | ------- | ---------- |
| Initialization   | ~0.1s   | 0%         |
| Frame processing | ~60-65s | 20%        |
| FFmpeg encoding  | ~240s   | 80%        |
| **Total**        | **~5m** | **100%**   |

The processor:

1. Generates PNG frames with alpha channel
2. Converts them to ProRes 4444 using FFmpeg (sequential)

### Optimization Tips

**Docker**:

- Allocate more CPUs: `docker run --cpus="4" ...`
- Increase memory: `docker run --memory="4g" ...`

**Local**:

- Install `PyOpenGL-accelerate` for better performance
- Use GPU-enabled system for faster OpenGL rendering

---

## Docker Details

### What's Included

The Docker image includes:

- Debian Bookworm (slim) base
- Python 3.11
- OpenGL/Mesa (software rendering with llvmpipe)
- GLFW libraries
- All Python dependencies (PyOpenGL, OpenCV, NumPy, GLFW)
- FFmpeg (latest static build)

**Build time**: ~5-10 minutes  
**Image size**: ~600MB

### Volume Mounts

The container expects two volume mounts:

- **`/input`** - Mount directory containing input videos
- **`/output`** - Mount directory where processed videos will be saved

Example:

```bash
docker run --rm \
  -v /path/to/videos:/input \
  -v /path/to/output:/output \
  chroma-key-processor \
  python process_video.py -i /input/video.mp4 -o /output/output.mov
```

### Environment Variables

Set these to customize OpenGL behavior:

```bash
docker run --rm \
  -e MESA_GL_VERSION_OVERRIDE=4.1 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py -i /input/video.mp4 -o /output/out.mov
```

Available variables:

- `MESA_GL_VERSION_OVERRIDE` - OpenGL version (default: 3.3)
- `LIBGL_ALWAYS_SOFTWARE` - Use software rendering (default: 1)
- `GALLIUM_DRIVER` - Mesa driver (default: llvmpipe)

### Interactive Shell (Debugging)

```bash
docker run --rm -it \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  /bin/sh
```

### Multi-platform Build

**For ARM64** (Apple Silicon, AWS Graviton):

```bash
docker buildx build --platform linux/arm64 \
  -f video-processor/Dockerfile \
  -t chroma-key-processor:arm64 .
```

**Multi-platform**:

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -f video-processor/Dockerfile \
  -t chroma-key-processor:latest .
```

---

## Troubleshooting

### OpenGL Errors

**"Failed to initialize GLFW"**:

- Ensure you have OpenGL support on your system
- Linux: `sudo apt-get install libglfw3 libglfw3-dev`
- macOS: Should work out of the box
- Windows: Install Visual C++ redistributables

**In Docker**:

```bash
# Try different Mesa driver
docker run -e GALLIUM_DRIVER=llvmpipe ...

# Or increase OpenGL version
docker run -e MESA_GL_VERSION_OVERRIDE=4.1 ...
```

### Shader Errors

**"Shader compilation errors"**:

- Ensure shader files are in `src/lib/shaders/`
- Check that `basic.vert` and `phase4.frag` exist
- In Docker: ensure you built from project root

**In Docker**:

```bash
cd chroma-key  # Must be at project root
docker build -f video-processor/Dockerfile -t chroma-key-processor .
```

### Permission Errors

**Docker output files have wrong permissions**:

```bash
# Run as current user
docker run --user $(id -u):$(id -g) ...
```

### Performance Issues

**Slow processing**:

- Install `PyOpenGL-accelerate` for better performance
- Use lower resolution input videos for testing
- Allocate more resources to Docker container
- Consider using GPU-enabled instance

### FFmpeg Errors

**"FFmpeg failed"**:

- Check that output directory is writable
- Ensure sufficient disk space
- Verify FFmpeg is installed (included in Docker)

---

## Advanced Usage

### Batch Processing

Create a script to process multiple videos:

```bash
#!/bin/bash
# process-batch.sh

INPUT_DIR="$(pwd)/static"
OUTPUT_DIR="$(pwd)/output"

for video in "$INPUT_DIR"/*.mp4; do
  filename=$(basename "$video" .mp4)
  echo "Processing: $filename"

  docker run --rm \
    -v "$INPUT_DIR:/input" \
    -v "$OUTPUT_DIR:/output" \
    chroma-key-processor \
    python process_video.py \
      -i "/input/$filename.mp4" \
      -o "/output/${filename}_keyed.mov" \
      --transparency 50 \
      --tolerance 50
done

echo "Batch processing complete!"
```

### Docker Compose

Create `docker-compose.yml`:

```yaml
version: "3.8"

services:
  processor:
    build:
      context: .
      dockerfile: video-processor/Dockerfile
    image: chroma-key-processor
    volumes:
      - ./static:/input
      - ./output:/output
    environment:
      - MESA_GL_VERSION_OVERRIDE=3.3
      - LIBGL_ALWAYS_SOFTWARE=1
    command: >
      python process_video.py
        -i /input/video.mp4
        -o /output/output.mov
        --transparency 50
        --tolerance 56.8
```

Run with:

```bash
docker-compose run --rm processor
```

### CI/CD Integration (GitHub Actions)

```yaml
name: Process Videos

on: [push]

jobs:
  process:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Build Docker image
        run: docker build -f video-processor/Dockerfile -t chroma-key-processor .

      - name: Process video
        run: |
          docker run --rm \
            -v ${{ github.workspace }}/static:/input \
            -v ${{ github.workspace }}/output:/output \
            chroma-key-processor \
            python process_video.py \
              -i /input/video.mp4 \
              -o /output/processed.mov

      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: processed-video
          path: output/processed.mov
```

### AWS ECS / Fargate Deployment

**1. Push to ECR**:

```bash
aws ecr create-repository --repository-name chroma-key-processor
docker tag chroma-key-processor:latest <account>.dkr.ecr.<region>.amazonaws.com/chroma-key-processor:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/chroma-key-processor:latest
```

**2. Create task definition** with:

- CPU: 2048 (2 vCPU)
- Memory: 4096 MB
- Mount EFS/S3 for input/output

**3. Run as batch job** using AWS Batch or ECS tasks

### AWS SageMaker

While the Docker container works, SageMaker has better alternatives:

- Use **SageMaker Processing Jobs** with custom container
- Or use native Python with CuPy for GPU acceleration
- Container is good for consistency but won't use SageMaker GPUs efficiently

---

## Requirements

- Python 3.8+
- OpenGL 3.3+ support
- PyOpenGL, OpenCV, GLFW, NumPy
- FFmpeg (for local use; included in Docker)

## Files

- **`process_video.py`** - Main video processor
- **`test_setup.py`** - Dependency verification script
- **`requirements.txt`** - Python dependencies
- **`Dockerfile`** - Docker image definition
- **`docker-entrypoint.sh`** - Docker entrypoint script

---

## Output Format

- **Codec**: ProRes 4444 (prores_ks)
- **Profile**: 4 (4444 with alpha)
- **Container**: MOV
- **Pixel Format**: yuva444p10le (10-bit YUV with alpha)
- **Resolution**: Same as input
- **FPS**: Same as input
- **Alpha Channel**: ✅ Preserved

---

## Notes

- Uses the same Phase 4 Ultra Key GLSL shader as the browser version
- Parameters match exactly with Phase 4 web UI
- Offscreen rendering (no window displayed)
- Docker uses Mesa software rendering (no GPU required)
- ProRes 4444 maintains full quality with alpha channel

---

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Verify your setup with `python test_setup.py`
3. Test with a short video clip first
4. Review OpenGL and FFmpeg logs for errors
