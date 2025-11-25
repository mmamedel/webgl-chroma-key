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
│   │       ├── basic.vert         # Shared vertex shader
│   │       ├── passthrough.frag   # Simple passthrough for color picking
│   │       ├── original.frag      # Original demo fragment shader
│   │       ├── phase1.frag        # Phase 1: Core parameters
│   │       ├── phase2.frag        # Phase 2: Matte generation
│   │       ├── phase3.frag        # Phase 3: Output modes
│   │       ├── phase4.frag        # Phase 4: Spill suppression
│   │       └── phase5.frag        # Phase 5: Matte cleanup
│   └── routes/
│       ├── +page.svelte           # Original Shadertoy shader demo
│       ├── phase1/+page.svelte    # Phase 1: Core parameters
│       ├── phase2/+page.svelte    # Phase 2: Matte generation
│       ├── phase3/+page.svelte    # Phase 3: Output modes
│       ├── phase4/+page.svelte    # Phase 4: Spill suppression
│       └── phase5/+page.svelte    # Phase 5: Matte cleanup (LATEST)
├── static/
│   ├── bg.jpg                     # Background image (original)
│   └── blue.jpg                   # Solid blue background
├── video-processor/
│   ├── process_video.py          # Python video processor (PyOpenGL)
│   ├── test_setup.py             # Verify Python dependencies
│   ├── requirements.txt          # Python dependencies
│   ├── Dockerfile                # Docker image definition
│   ├── .dockerignore             # Docker ignore patterns
│   ├── docker-run.sh             # Docker helper script
│   ├── PROCESS_VIDEO.md          # Video processing documentation
│   ├── DOCKER.md                 # Docker usage guide
│   └── README.md                 # Video processor quick start
├── docs/
│   ├── ultra-key-spec.md          # Complete Ultra Key specification
│   ├── ultra-key-use-cases.md     # Real-world use cases and workflows
│   ├── ultra-key-shader-gap-analysis.md # Gap analysis
│   └── implementation-details.md  # Technical implementation guide
└── shadertoy-chroma-key-shader   # Original shader code reference
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

### ✅ Phase 2 (`/phase2`) - COMPLETE

**Matte Generation Enhancement**

Implemented:

- ✅ Highlight control (0-100) - handles bright background areas
- ✅ Shadow control (0-100) - handles dark background areas
- ✅ Pedestal control (0-100) - shifts entire alpha range
- ✅ Luminance-based masking
- ✅ Improved alpha falloff curves

**Key Features:**

- Luminance-aware keying for better control over bright and dark areas
- Adjustable pedestal to shift the entire alpha range
- Maintains all Phase 1 features

### ✅ Phase 3 (`/phase3`) - COMPLETE

**Output Modes**

Implemented:

- ✅ Status mode with color-coded diagnostics
  - Green = transparent (good key)
  - Red = partial transparency (edge/problem areas)
  - White = opaque (foreground)
- ✅ Enhanced output mode switching

**Key Features:**

- Visual quality assessment with Status mode
- Helps identify problem areas and edge quality
- All previous phase features included

### ✅ Phase 4 (`/phase4`) - COMPLETE

**Spill Suppression**

Implemented:

- ✅ Configurable spill removal (0-100)
- ✅ Intelligent color desaturation
- ✅ Key color component reduction
- ✅ Luminance preservation

**Key Features:**

- Removes green/blue color spill from subjects
- Adjustable strength from 0 (no suppression) to 100 (maximum removal)
- Works on both green and blue screen setups
- All previous phase features included

### ✅ Phase 5 (`/phase5`) - COMPLETE

**Matte Cleanup**

Implemented:

- ✅ Contrast (0-200) - Cleans up semi-transparent areas
- ✅ Mid Point (0-100) - Adjusts contrast pivot point
- ✅ Choke (-20 to 20) - Erode/dilate matte edges
- ✅ Soften (0-20) - Gaussian blur for smoother edges
- ✅ EyeDropper API color picker - Pick colors from anywhere on screen
- ✅ Video file upload support
- ✅ GPU-optimized render loop (pauses when video is static)

**Key Features:**

- Professional matte cleanup controls
- Single-pass implementation of choke and soften
- Advanced color picker with visual feedback
- Custom video support via file upload
- All previous phase features included

## 🎨 Features

### Current (All Phases Complete!)

**Browser Demo:**

- Real-time WebGL shader processing
- Video playback with keying
- Interactive parameter controls
- Preset system (Default/Aggressive/Custom)
- Advanced EyeDropper API color picker
- Video file upload support
- GPU-optimized render loop
- Multiple output modes (Composite/Alpha Channel/Status)
- Responsive UI

**Implemented Parameters (13 total):**

- **Matte Generation (5):** Key Color, Transparency, Tolerance, Highlight, Shadow, Pedestal
- **Spill Suppression (1):** Spill Amount
- **Matte Cleanup (4):** Contrast, Mid Point, Choke, Soften
- **Output (3 modes):** Composite, Alpha Channel, Status

**Video Processing:**

- Offline video rendering with same shaders
- Command-line interface
- GPU-accelerated (OpenGL)
- Batch processing ready
- Same parameters as browser demo
- Export to MP4
- Progress tracking

### Future Enhancements (Optional)

Additional Ultra Key features that could be added:

- Color Correction (3 params): Saturation, Hue shift, Luminance
- Advanced Spill Controls: Range, Desaturate, Spillage parameters
- Multi-pass choke/soften for higher quality edge refinement

## 📊 Progress

- **Phase 1:** ✅ Complete - Core Parameter System
- **Phase 2:** ✅ Complete - Matte Generation Enhancement
- **Phase 3:** ✅ Complete - Output Modes
- **Phase 4:** ✅ Complete - Spill Suppression
- **Phase 5:** ✅ Complete - Matte Cleanup

**Total Implementation:** 13 professional chroma key parameters + advanced UI features

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

## 🎉 Completed Features

All core chroma keying features have been implemented:

- ✅ Complete matte generation controls (Transparency, Tolerance, Highlight, Shadow, Pedestal)
- ✅ Professional spill suppression
- ✅ Matte cleanup tools (Contrast, Mid Point, Choke, Soften)
- ✅ Multiple output modes including diagnostic Status view
- ✅ Advanced EyeDropper API color picker (pick from anywhere on screen)
- ✅ Custom video upload support
- ✅ GPU-optimized rendering (pauses when static)

## 📈 Future Enhancements (Optional)

Potential additions for even more advanced workflows:

1. Color Correction controls (Saturation, Hue, Luminance adjustments)
2. Enhanced spill suppression (Range, Desaturate, Spillage parameters)
3. Multi-pass choke/soften for premium edge quality
4. Background replacement with custom images/videos
5. Real-time video export functionality

## 🤝 Contributing

This is a learning project to understand professional chroma keying algorithms. Feedback and improvements welcome!

## 📄 License

MIT
