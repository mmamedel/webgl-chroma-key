# Ultra Key to WebGPU Shader - Gap Analysis

## Executive Summary

Analysis of current Shadertoy chroma key shader vs. Adobe Premiere Pro Ultra Key requirements for WebGPU implementation.

**Current:** Basic keying with hardcoded parameters  
**Target:** Full Ultra Key feature parity with 18 adjustable parameters

---

## Current Shader Capabilities

### What Works Now

```glsl
vec3 backgroundColor = vec3(0.157, 0.576, 0.129);  // HARDCODED green
vec3 weights = vec3(4., 1., 2.);                   // HARDCODED weights
float dist = length(weights * (target - hsv));
return 1. - clamp(3. * dist - 1.5, 0., 1.);       // HARDCODED thresholds
color = changeSaturation(color, 0.5);              // HARDCODED spill fix
```

**Features:**

- ✅ RGB to HSV conversion
- ✅ Weighted HSV distance calculation
- ✅ Basic threshold-based alpha
- ✅ Simple saturation reduction (50%)
- ✅ Alpha blending

**Quality:** Basic - works for simple cases only

---

## Complete Gap Analysis

### Missing: 17 of 18 Ultra Key Parameters

| Category              | Parameter    | Current       | Required                                    | Priority |
| --------------------- | ------------ | ------------- | ------------------------------------------- | -------- |
| **System**            | Key Color    | Hardcoded     | User-selectable vec3                        | CRITICAL |
|                       | Output Mode  | None          | 4 modes (Composite/Alpha/Status/ColorMatte) | HIGH     |
| **Matte Generation**  | Transparency | Fixed (3.0)   | 0-100 adjustable                            | CRITICAL |
|                       | Highlight    | None          | 0-100                                       | HIGH     |
|                       | Shadow       | None          | 0-100                                       | HIGH     |
|                       | Tolerance    | Fixed weights | 0-100                                       | CRITICAL |
|                       | Pedestal     | None          | 0-100                                       | MEDIUM   |
| **Matte Cleanup**     | Choke        | None          | 0-100 (erosion/dilation)                    | MEDIUM   |
|                       | Soften       | None          | 0-100 (edge blur)                           | MEDIUM   |
|                       | Contrast     | None          | 0-100                                       | MEDIUM   |
|                       | Mid Point    | None          | 0-100                                       | LOW      |
| **Spill Suppression** | Desaturate   | Fixed (50%)   | 0-100                                       | MEDIUM   |
|                       | Range        | None          | 0-100                                       | MEDIUM   |
|                       | Spillage     | Fixed (50%)   | 0-100                                       | MEDIUM   |
|                       | Luma         | None          | 0-100                                       | LOW      |
| **Color Correction**  | Saturation   | None          | 0-200                                       | LOW      |
|                       | Hue          | None          | -180 to +180                                | LOW      |
|                       | Luminance    | None          | 0-200                                       | LOW      |

---

## Critical Missing Features

### 1. User-Configurable Key Color

**Impact:** Cannot key different backgrounds  
**Current:** `vec3(0.157, 0.576, 0.129)` hardcoded  
**Needed:** Pass as uniform, equivalent to eyedropper selection

### 2. Adjustable Matte Generation

**Impact:** Cannot adapt to different footage quality  
**Current:** Magic numbers `3.0` and `1.5`  
**Needed:**

```glsl
float threshold = 0.5 + (transparency - 50.0) * 0.01;
float slope = 3.0 + (transparency - 50.0) * 0.05;
return 1.0 - smoothstep(0.0, threshold, dist * slope);
```

### 3. Output Modes for Evaluation

**Impact:** Users cannot diagnose matte quality  
**Needed:**

- **Alpha Channel:** Grayscale matte (white=opaque, black=transparent)
- **Status:** Color-coded diagnostic (red=bad, yellow=marginal, blue=OK)
- **Composite:** Final result

### 4. Highlight/Shadow Controls

**Impact:** Cannot handle uneven lighting  
**Needed:** Luminance-aware keying

```glsl
float luma = dot(color, vec3(0.299, 0.587, 0.114));
if (luma > 0.7) apply_highlight_adjustment();
if (luma < 0.3) apply_shadow_adjustment();
```

### 5. Advanced Spill Suppression

**Impact:** Green cast remains on subject  
**Current:** Uniform 50% desaturation  
**Needed:**

- Detect spill proximity to key color
- Shift hue toward complementary (green→magenta)
- Range-based targeting
- Luminance compensation

### 6. Matte Cleanup

**Impact:** Cannot refine edges  
**Needed:** Multi-pass operations

- Choke: Morphological erosion/dilation
- Soften: Edge detection + selective blur
- Contrast: Alpha curve adjustment

---

## Implementation Roadmap

### Phase 1: Core Parameters (CRITICAL) - 2-3 days

1. Create uniform structure for all parameters
2. Replace hardcoded key color with uniform
3. Replace magic numbers with transparency/tolerance parameters
4. Add Default/Aggressive preset system

### Phase 2: Matte Generation (HIGH) - 5-7 days

1. Implement adjustable Transparency
2. Implement Tolerance (adjust weights dynamically)
3. Add Highlight control (luminance-based masking)
4. Add Shadow control (luminance-based masking)
5. Add Pedestal (shift alpha range)
6. Improve alpha falloff curves

### Phase 3: Output Modes (HIGH) - 3-4 days

1. Add output mode selection uniform
2. Implement Alpha Channel mode
3. Implement Status mode with color-coding
4. Implement Composite mode (current)

### Phase 4: Spill Suppression (MEDIUM) - 4-5 days

1. Detect spill (color proximity detection)
2. Hue shift toward complementary color
3. Range parameter (control affected spectrum)
4. Desaturate parameter
5. Spillage parameter (overall strength)
6. Luma compensation

### Phase 5: Matte Cleanup (MEDIUM-COMPLEX) - 7-10 days

1. Implement Choke (may need compute shader)
2. Implement Soften (edge detection + blur)
3. Implement Contrast (alpha curves)
4. Implement Mid Point (pivot adjustment)

**Note:** May require multi-pass rendering or compute shaders

### Phase 6: Color Correction (LOW) - 2-3 days

1. Saturation adjustment
2. Hue shift
3. Luminance adjustment

**Total Estimated Effort:** 6-8 weeks for full parity

---

## Recommended Shader Structure

```glsl
struct UltraKeyParams {
    // System
    vec3 keyColor;
    int outputMode;

    // Matte Generation
    float transparency, highlight, shadow, tolerance, pedestal;

    // Matte Cleanup
    float choke, soften, contrast, midPoint;

    // Spill Suppression
    float desaturate, range, spillage, luma;

    // Color Correction
    float saturation, hue, luminance;
};

void main() {
    vec3 color = texture(input, uv).rgb;

    // Pipeline
    float alpha = generateMatte(color, params);          // Phase 2
    alpha = cleanupMatte(alpha, uv, params);            // Phase 5 (multi-pass)
    color = suppressSpill(color, alpha, params);        // Phase 4
    color = colorCorrect(color, alpha, params);         // Phase 6
    vec4 output = selectOutputMode(color, alpha, params); // Phase 3

    fragColor = output;
}
```

---

## Algorithm Improvements Needed

### Better Distance Calculation

```glsl
// Current: Fixed weights and threshold
float dist = length(vec3(4., 1., 2.) * (target - hsv));
return 1. - clamp(3. * dist - 1.5, 0., 1.);

// Improved: Adjustable parameters
float tolFactor = 1.0 + (tolerance - 50.0) * 0.02;
vec3 weights = vec3(4.0, 1.0, 2.0) * tolFactor;
float dist = length(weights * (targetHSV - hsv));
float threshold = 0.5 + (transparency - 50.0) * 0.01;
return 1.0 - smoothstep(0.0, threshold, dist);
```

### Luminance-Aware Keying

```glsl
float luma = dot(color, vec3(0.299, 0.587, 0.114));

// Bright areas (hot spots)
float highlightMask = smoothstep(0.6, 0.9, luma);
alpha = mix(alpha, adjustedAlpha, highlightMask * highlight * 0.01);

// Dark areas (shadows)
float shadowMask = smoothstep(0.3, 0.0, luma);
alpha = mix(alpha, adjustedAlpha, shadowMask * shadow * 0.01);
```

### Spill Detection & Correction

```glsl
// Detect spill proximity
vec3 hsv = rgb2hsv(color);
vec3 keyHSV = rgb2hsv(keyColor);
float hueDist = abs(hsv.x - keyHSV.x);
float spillAmount = smoothstep(range * 0.01, 0.0, hueDist);

// Shift toward complementary
vec3 complementary = getComplementaryColor(keyColor);
color = shiftHue(color, complementary, spillAmount * spillage);

// Desaturate
float luma = getLuminance(color);
color = mix(color, vec3(luma), spillAmount * desaturate * 0.01);
```

---

## WebGPU-Specific Considerations

### Uniform Buffer Layout (16-byte aligned)

```rust
struct UltraKeyUniforms {
    key_color: [f32; 3],
    output_mode: u32,

    matte_gen: [f32; 4],     // transparency, highlight, shadow, tolerance
    matte_gen2: [f32; 4],    // pedestal, ...

    matte_cleanup: [f32; 4], // choke, soften, contrast, midPoint
    spill: [f32; 4],         // desaturate, range, spillage, luma
    color_correct: [f32; 4], // saturation, hue, luminance, ...
}
```

### Multi-Pass for Matte Cleanup

```
Pass 1: Generate Matte (Fragment Shader)
  → Render to texture (RGBA with alpha channel)

Pass 2: Cleanup Matte (Compute Shader - optional for choke/soften)
  → Process alpha channel
  → Output refined alpha texture

Pass 3: Spill & Composite (Fragment Shader)
  → Use refined alpha
  → Apply spill suppression
  → Color correction
  → Final composite
```

---

## Minimum Viable Product (MVP)

**Goal:** Match Ultra Key Default preset - 2-3 weeks

**Must Have:**

1. User-selectable key color
2. Transparency parameter
3. Tolerance parameter
4. Alpha Channel output mode
5. Basic adjustable spill suppression

**This enables:** Sign language video workflow from use cases (key once per signer, copy settings)

---

## Key Challenges

### High Complexity

1. **Matte Cleanup** - Requires morphological operations (erosion/dilation)
2. **Edge Detection** - Needed for selective soften
3. **Multi-Pass Architecture** - Coordinate multiple shader stages

### Medium Complexity

1. **Spill Detection** - Color space analysis
2. **Status Mode** - Alpha quality analysis & color coding
3. **Luminance Masking** - Separate bright/dark handling

### Low Complexity

1. **Parameter System** - Straightforward uniforms
2. **Color Correction** - Standard image processing
3. **Output Modes** - Rendering logic

---

## Success Criteria

From use case document:

### Technical Quality

- Solid white subject in Alpha Channel mode
- Solid black background in Alpha Channel mode
- No gray holes in subject
- Clean edges without harsh outlines
- No visible green/blue spill

### Production Efficiency

- One key per subject (under consistent conditions)
- 1-5 minutes to adjust per clip
- Successful batch application
- Real-time preview (60 FPS @ 1080p)

### Visual Quality

- Natural integration with background
- Preserved fine detail (hair, fingers)
- Appropriate edge softness
- Natural skin tones

---

## Conclusion

**Current shader:** 5% of Ultra Key functionality  
**MVP (3 weeks):** 40% - enough for basic production use  
**Full parity (8 weeks):** 95% - professional-grade replacement

**Main Technical Debt:**

- 17 missing parameters (all must be added)
- No matte evaluation tools (output modes)
- Primitive alpha generation (no luminance awareness)
- Basic spill suppression (no intelligent targeting)
- No edge refinement (cleanup system)
