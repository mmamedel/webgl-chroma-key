# Chroma Key WebGL Demo - Ultra Key Implementation

A progressive implementation of Adobe Premiere Pro's Ultra Key effect using WebGL shaders in SvelteKit.

## 🚀 Quick Start

### Browser Demo

```bash
# Install dependencies
pnpm install

# Start dev server
pnpm dev

# Open http://localhost:5173
```

### Video Processing (Python)

**Option 1: Docker (Linux/Production)**

```bash
# Build image (~5-10 min)
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

# See video-processor/DOCKER.md for details
```

**Option 2: Local Python**

```bash
# Navigate to video processor
cd video-processor

# Install Python dependencies
pip install -r requirements.txt

# Test setup
python test_setup.py

# Process video
python process_video.py \
  -i ../static/060_INSIGHT-4_Paragraph_20251117_113546.mp4 \
  -o ../output.mp4 \
  -b ../static/blue.jpg

# See PROCESS_VIDEO.md for detailed usage
```

## 📁 Project Structure

```
chroma-key/
├── src/
│   ├── lib/
│   │   └── shaders/
│   │       ├── basic.vert     # Shared vertex shader
│   │       ├── original.frag  # Original demo fragment shader
│   │       └── phase1.frag    # Phase 1 fragment shader
│   └── routes/
│       ├── +page.svelte       # Original Shadertoy shader demo
│       └── phase1/
│           └── +page.svelte   # Phase 1: Core parameters
├── static/
│   ├── bg.jpg                   # Background image (original)
│   └── blue.jpg                 # Solid blue background
├── video-processor/
│   ├── process_video.py      # Python video processor (PyOpenGL)
│   ├── test_setup.py         # Verify Python dependencies
│   ├── requirements.txt      # Python dependencies
│   ├── Dockerfile            # Docker image definition
│   ├── .dockerignore         # Docker ignore patterns
│   ├── docker-run.sh         # Docker helper script
│   ├── PROCESS_VIDEO.md      # Video processing documentation
│   ├── DOCKER.md             # Docker usage guide
│   └── README.md             # Video processor quick start
├── docs/
│   ├── ultra-key-spec.md      # Complete Ultra Key specification
│   ├── ultra-key-use-cases.md # Real-world use cases and workflows
│   ├── ultra-key-shader-gap-analysis.md # Gap analysis
│   └── implementation-details.md # Technical implementation guide
└── shadertoy-chroma-key-shader # Original shader code reference
```

## 🎯 Implementation Phases

### ✅ Original Demo (`/`)

- Basic Shadertoy chroma key shader
- Hardcoded parameters
- RGB to HSV conversion
- Simple threshold-based keying

**Limitations:**

- Fixed green key color
- No user controls
- Basic spill suppression (50% saturation)

### ✅ Phase 1 (`/phase1`) - COMPLETE

**Core Parameter System**

Implemented:

- ✅ User-selectable key color (eyedropper from video center)
- ✅ Adjustable Transparency parameter (0-100)
- ✅ Adjustable Tolerance parameter (0-100)
- ✅ Preset system (Default/Aggressive/Custom)
- ✅ Output modes (Composite/Alpha Channel)
- ✅ Real-time parameter updates
- ✅ Improved HSV distance calculation with hue wraparound

**New Shader Features:**

```glsl
// Tolerance affects weight multiplication
float tolFactor = 1.0 + (u_tolerance - 50.0) * 0.02;
vec3 weights = vec3(4.0, 1.0, 2.0) * tolFactor;

// Transparency affects threshold and slope
float threshold = 0.5 + (u_transparency - 50.0) * 0.01;
float slope = 3.0 + (u_transparency - 50.0) * 0.05;

// Smooth falloff with adjustable parameters
return 1.0 - smoothstep(0.0, threshold, dist * slope);
```

### 🔄 Phase 2 (Next) - Matte Generation Enhancement

**Goal:** Add luminance-aware keying

Will implement:

- [ ] Highlight control (0-100) - handles bright background areas
- [ ] Shadow control (0-100) - handles dark background areas
- [ ] Pedestal control (0-100) - shifts entire alpha range
- [ ] Luminance-based masking
- [ ] Improved alpha falloff curves

### 🔄 Phase 3 - Output Modes

Will implement:

- [ ] Status mode with color-coded diagnostics
  - Red = poor quality
  - Yellow = marginal
  - Blue = acceptable
  - Black/White = ideal
- [ ] Color Matte mode

### 🔄 Phase 4 - Spill Suppression

Will implement:

- [ ] Intelligent spill detection
- [ ] Hue shift toward complementary color
- [ ] Range parameter (control affected spectrum)
- [ ] Desaturate parameter (adjustable)
- [ ] Spillage parameter (overall strength)
- [ ] Luma compensation

### 🔄 Phase 5 - Matte Cleanup (Multi-Pass)

Will implement:

- [ ] Choke (erosion/dilation) - requires compute shader
- [ ] Soften (edge blur) - edge detection + selective blur
- [ ] Contrast (alpha curves)
- [ ] Mid Point (pivot adjustment)

### 🔄 Phase 6 - Color Correction

Will implement:

- [ ] Saturation adjustment (0-200%)
- [ ] Hue shift (-180 to +180°)
- [ ] Luminance adjustment (0-200%)

## 🎨 Features

### Current (Phase 1)

**Browser Demo:**

- Real-time WebGL shader processing
- Video playback with keying
- Interactive parameter controls
- Preset system
- Key color picker
- Output mode switching
- Responsive UI

**Video Processing:**

- Offline video rendering with same shaders
- Command-line interface
- GPU-accelerated (OpenGL)
- Batch processing ready
- Same parameters as browser demo
- Export to MP4
- Progress tracking

### Target (Full Ultra Key Parity)

18 total parameters across 4 categories:

- Matte Generation (5 params)
- Matte Cleanup (4 params)
- Spill Suppression (4 params)
- Color Correction (3 params)
- System (2 params: key color, output mode)

## 📊 Progress

- **Phase 1:** ✅ Complete (5/18 parameters = 28%)
- **Phase 2:** 🔄 Next (3 parameters)
- **Phase 3:** 📋 Planned
- **Phase 4:** 📋 Planned
- **Phase 5:** 📋 Planned (complex, multi-pass)
- **Phase 6:** 📋 Planned

## 🛠 Tech Stack

### Browser Demo

- **Framework:** SvelteKit 5
- **Graphics:** WebGL 1.0
- **Language:** GLSL (fragment shaders)
- **Build Tool:** Vite
- **Package Manager:** pnpm

### Video Processing

- **Language:** Python 3.8+
- **Graphics:** PyOpenGL (OpenGL 3.3+)
- **Video I/O:** OpenCV (cv2)
- **Windowing:** GLFW (headless rendering)

## 📚 Documentation

Comprehensive documentation in `/docs`:

1. **ultra-key-spec.md** - Complete feature specification

   - All 18 parameters with ranges and defaults
   - User workflow patterns
   - Best practices from training materials

2. **ultra-key-use-cases.md** - Real-world usage

   - Sign language video production workflow
   - Problem scenarios and solutions
   - Quality assessment workflows

3. **ultra-key-shader-gap-analysis.md** - Implementation roadmap

   - Current vs. target comparison
   - 6-phase implementation plan
   - Technical complexity breakdown

4. **implementation-details.md** - Technical guide
   - Complete GLSL algorithm implementations
   - WebGPU uniform structures
   - Multi-pass architecture
   - Performance optimization tips

## 🎯 Use Cases

Primary use case: **Sign language video production**

- Key once per signer
- Copy settings to all clips
- Batch processing efficiency
- 1-5 minute adjustment time per clip

## 🔍 Testing

Test with included assets:

- `static/060_INSIGHT-4_Paragraph_20251117_113546.mp4` - Green screen footage
- `static/blue.jpg` - Replacement background

Evaluate using:

- **Alpha Channel mode** - Check matte quality (white=opaque, black=transparent)
- **Composite mode** - Check final visual result
- **Parameter adjustment** - Test responsiveness

## 🚧 Known Limitations (Phase 1)

- No highlight/shadow controls (footage must be evenly lit)
- Basic spill suppression (50% saturation, not adjustable)
- No edge refinement (choke, soften)
- Limited output modes (only 2 of 4)
- Key color picker only samples center pixel

## 📈 Next Steps

1. Implement Phase 2 (Highlight/Shadow/Pedestal)
2. Add Status mode for diagnostic view
3. Implement advanced spill suppression
4. Design multi-pass architecture for matte cleanup
5. Performance optimization
6. Add more sophisticated key color picker (5x5 sample, click anywhere)

## 🤝 Contributing

This is a learning project to understand professional chroma keying algorithms. Feedback and improvements welcome!

## 📄 License

MIT
