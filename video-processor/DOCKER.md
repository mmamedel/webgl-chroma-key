# Docker Usage for Video Processor

Run the chroma key video processor in a containerized environment with all dependencies.

## Building the Image

**Important:** Build from the project root (not from video-processor directory).

```bash
# Navigate to project root
cd /path/to/chroma-key

# Build the Docker image (~5-10 minutes)
docker build -f video-processor/Dockerfile -t chroma-key-processor .
```

### What's Included

The image includes:

- Debian Bookworm (slim) base
- Python 3.11
- OpenGL/Mesa (software rendering with llvmpipe)
- GLFW libraries
- All Python dependencies (PyOpenGL, OpenCV, NumPy, GLFW)

**Build time:** ~5-10 minutes (uses pre-built binary wheels)  
**Image size:** ~600MB

## Quick Start

### Basic Usage

```bash
docker run --rm \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py \
    -i /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
    -o /output/output.mp4 \
    -b /input/blue.jpg
```

### With Custom Parameters

```bash
docker run --rm \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py \
    -i /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
    -o /output/output.mp4 \
    -b /input/blue.jpg \
    --transparency 60 \
    --tolerance 45
```

### Interactive Shell (for debugging)

```bash
docker run --rm -it \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  /bin/sh
```

## Volume Mounts

The container expects two volume mounts:

- **`/input`** - Mount directory containing input videos and backgrounds
- **`/output`** - Mount directory where processed videos will be saved

Example:

```bash
-v /path/to/videos:/input \
-v /path/to/output:/output
```

## Environment Variables

Set these to customize OpenGL behavior:

```bash
docker run --rm \
  -e MESA_GL_VERSION_OVERRIDE=4.1 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -v $(pwd)/static:/input \
  -v $(pwd):/output \
  chroma-key-processor \
  python process_video.py -i /input/video.mp4 -o /output/out.mp4 -b /input/bg.jpg
```

Available variables:

- `MESA_GL_VERSION_OVERRIDE` - OpenGL version (default: 3.3)
- `LIBGL_ALWAYS_SOFTWARE` - Use software rendering (default: 1)
- `GALLIUM_DRIVER` - Mesa driver (default: softpipe)

## Complete Examples

### Process Single Video

```bash
#!/bin/bash
docker run --rm \
  -v "$(pwd)/static:/input:ro" \
  -v "$(pwd)/output:/output" \
  chroma-key-processor \
  python process_video.py \
    --input /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
    --output /output/keyed-video.mp4 \
    --background /input/blue.jpg \
    --transparency 50 \
    --tolerance 50
```

### Generate Alpha Matte

```bash
docker run --rm \
  -v "$(pwd)/static:/input:ro" \
  -v "$(pwd)/output:/output" \
  chroma-key-processor \
  python process_video.py \
    -i /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
    -o /output/matte.mp4 \
    -b /input/blue.jpg \
    --output-mode 1
```

### Batch Processing

Create a script to process multiple videos:

```bash
#!/bin/bash
# process-batch.sh

INPUT_DIR="$(pwd)/static"
OUTPUT_DIR="$(pwd)/output"
BACKGROUND="$INPUT_DIR/blue.jpg"

for video in "$INPUT_DIR"/*.mp4; do
  filename=$(basename "$video" .mp4)
  echo "Processing: $filename"

  docker run --rm \
    -v "$INPUT_DIR:/input:ro" \
    -v "$OUTPUT_DIR:/output" \
    chroma-key-processor \
    python process_video.py \
      -i "/input/$filename.mp4" \
      -o "/output/${filename}_keyed.mp4" \
      -b /input/blue.jpg \
      --transparency 50 \
      --tolerance 50
done

echo "Batch processing complete!"
```

## Docker Compose (Optional)

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
      - ./static:/input:ro
      - ./output:/output
    environment:
      - MESA_GL_VERSION_OVERRIDE=3.3
      - LIBGL_ALWAYS_SOFTWARE=1
    command: >
      python process_video.py
        -i /input/060_INSIGHT-4_Paragraph_20251117_113546.mp4
        -o /output/output.mp4
        -b /input/blue.jpg
```

Run with:

```bash
docker-compose run --rm processor
```

## Performance Notes

### Software Rendering

- Container uses Mesa software rendering (no GPU acceleration)
- ~5-15 fps processing speed (CPU-dependent)
- Good for batch processing, not real-time

### Optimization Tips

1. **Use smaller videos for testing** - Test with short clips first
2. **CPU allocation** - Allocate more CPUs to container:
   ```bash
   docker run --cpus="4" ...
   ```
3. **Memory** - Increase if processing large videos:
   ```bash
   docker run --memory="4g" ...
   ```

## Troubleshooting

### OpenGL Errors

If you see OpenGL-related errors:

```bash
# Try different Mesa driver
docker run -e GALLIUM_DRIVER=llvmpipe ...

# Or increase OpenGL version
docker run -e MESA_GL_VERSION_OVERRIDE=4.1 ...
```

### Permission Errors

If output files have wrong permissions:

```bash
# Run as current user
docker run --user $(id -u):$(id -g) ...
```

### Shader Not Found

If shaders aren't found, ensure you built from project root:

```bash
cd chroma-key  # Must be at root
docker build -f video-processor/Dockerfile -t chroma-key-processor .
```

### OpenCV Issues

The container uses `opencv-python-headless` (no GUI dependencies). If you need full OpenCV:

```bash
# Modify Dockerfile: replace opencv-python-headless with opencv-python
# Then rebuild
```

## CI/CD Integration

### GitHub Actions Example

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
              -o /output/processed.mp4 \
              -b /input/blue.jpg

      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: processed-video
          path: output/processed.mp4
```

## AWS ECS / Fargate Deployment

For production deployments:

1. **Push to ECR**:

```bash
aws ecr create-repository --repository-name chroma-key-processor
docker tag chroma-key-processor:latest <account>.dkr.ecr.<region>.amazonaws.com/chroma-key-processor:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/chroma-key-processor:latest
```

2. **Create task definition** with:

   - CPU: 2048 (2 vCPU)
   - Memory: 4096 MB
   - Mount EFS/S3 for input/output

3. **Run as batch job** using AWS Batch or ECS tasks

## SageMaker Integration

While the Docker container works, SageMaker has better alternatives:

- Use **SageMaker Processing Jobs** with custom container
- Or use native Python with CuPy for GPU acceleration
- Container is good for consistency but won't use SageMaker GPUs

## Size Information

- **Base image**: ~130 MB (Debian Bookworm slim)
- **With dependencies**: ~600 MB
- **Full image**: ~600 MB

Reasonable size with fast build times thanks to binary wheels.

## Building for Different Platforms

### For ARM64 (Apple Silicon, AWS Graviton)

```bash
docker buildx build --platform linux/arm64 \
  -f video-processor/Dockerfile \
  -t chroma-key-processor:arm64 .
```

### Multi-platform

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -f video-processor/Dockerfile \
  -t chroma-key-processor:latest .
```

## Next Steps

1. Test locally first: `docker run ... --help`
2. Process a short video to verify
3. Adjust parameters as needed
4. Scale to batch processing
5. Deploy to cloud if needed
