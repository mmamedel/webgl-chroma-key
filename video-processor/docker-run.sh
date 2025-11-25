#!/bin/bash
# Quick Docker run script for video processor

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
INPUT=""
OUTPUT=""
BACKGROUND=""
TRANSPARENCY=50
TOLERANCE=50
OUTPUT_MODE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--input)
      INPUT="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    -b|--background)
      BACKGROUND="$2"
      shift 2
      ;;
    --transparency)
      TRANSPARENCY="$2"
      shift 2
      ;;
    --tolerance)
      TOLERANCE="$2"
      shift 2
      ;;
    --output-mode)
      OUTPUT_MODE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./docker-run.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -i, --input FILE         Input video file (relative to project root)"
      echo "  -o, --output FILE        Output video file (relative to project root)"
      echo "  -b, --background FILE    Background image (relative to project root)"
      echo "  --transparency VALUE     Transparency (0-100, default: 50)"
      echo "  --tolerance VALUE        Tolerance (0-100, default: 50)"
      echo "  --output-mode MODE       0=Composite, 1=Alpha (default: 0)"
      echo "  -h, --help               Show this help"
      echo ""
      echo "Example:"
      echo "  ./docker-run.sh -i static/video.mp4 -o output.mp4 -b static/blue.jpg"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [[ -z "$INPUT" ]] || [[ -z "$OUTPUT" ]] || [[ -z "$BACKGROUND" ]]; then
  echo -e "${RED}Error: Missing required arguments${NC}"
  echo "Run with --help for usage information"
  exit 1
fi

# Get project root (parent of video-processor)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Convert paths to absolute
INPUT_ABS="$PROJECT_ROOT/$INPUT"
OUTPUT_ABS="$PROJECT_ROOT/$OUTPUT"
BACKGROUND_ABS="$PROJECT_ROOT/$BACKGROUND"

# Check if files exist
if [[ ! -f "$INPUT_ABS" ]]; then
  echo -e "${RED}Error: Input file not found: $INPUT${NC}"
  exit 1
fi

if [[ ! -f "$BACKGROUND_ABS" ]]; then
  echo -e "${RED}Error: Background file not found: $BACKGROUND${NC}"
  exit 1
fi

# Get directory names
INPUT_DIR=$(dirname "$INPUT_ABS")
OUTPUT_DIR=$(dirname "$OUTPUT_ABS")
INPUT_FILE=$(basename "$INPUT_ABS")
OUTPUT_FILE=$(basename "$OUTPUT_ABS")
BACKGROUND_DIR=$(dirname "$BACKGROUND_ABS")
BACKGROUND_FILE=$(basename "$BACKGROUND_ABS")

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Check if Docker image exists
if ! docker image inspect chroma-key-processor >/dev/null 2>&1; then
  echo -e "${YELLOW}Docker image not found. Building...${NC}"
  cd "$PROJECT_ROOT"
  docker build -f video-processor/Dockerfile -t chroma-key-processor .
  echo -e "${GREEN}Build complete!${NC}"
fi

# Run Docker container
echo -e "${GREEN}Processing video...${NC}"
echo "Input: $INPUT"
echo "Output: $OUTPUT"
echo "Background: $BACKGROUND"
echo "Transparency: $TRANSPARENCY, Tolerance: $TOLERANCE"
echo ""

docker run --rm \
  -v "$INPUT_DIR:/input:ro" \
  -v "$OUTPUT_DIR:/output" \
  -v "$BACKGROUND_DIR:/background:ro" \
  chroma-key-processor \
  python process_video.py \
    --input "/input/$INPUT_FILE" \
    --output "/output/$OUTPUT_FILE" \
    --background "/background/$BACKGROUND_FILE" \
    --transparency "$TRANSPARENCY" \
    --tolerance "$TOLERANCE" \
    --output-mode "$OUTPUT_MODE"

if [[ $? -eq 0 ]]; then
  echo ""
  echo -e "${GREEN}✅ Success! Output saved to: $OUTPUT${NC}"
else
  echo ""
  echo -e "${RED}❌ Processing failed${NC}"
  exit 1
fi
