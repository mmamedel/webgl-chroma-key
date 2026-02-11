// Phase 6: WebGPU Chroma Key Shader
// Ported from GLSL to WGSL

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texCoord: vec2f,
};

struct Uniforms {
    resolution: vec2f,
    keyColor: vec3f,
    transparency: f32,
    tolerance: f32,
    highlight: f32,
    shadow: f32,
    pedestal: f32,
    spillSuppression: f32,
    contrast: f32,
    midPoint: f32,
    choke: f32,
    soften: f32,
    outputMode: i32,
    _padding: f32,
};

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTexture: texture_external;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

@vertex
fn vs(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    // Full-screen quad positions
    let positions = array<vec2f, 6>(
        vec2f(-1.0, -1.0),
        vec2f( 1.0, -1.0),
        vec2f(-1.0,  1.0),
        vec2f(-1.0,  1.0),
        vec2f( 1.0, -1.0),
        vec2f( 1.0,  1.0),
    );
    
    // Texture coordinates (flip Y for video)
    let texCoords = array<vec2f, 6>(
        vec2f(0.0, 1.0),
        vec2f(1.0, 1.0),
        vec2f(0.0, 0.0),
        vec2f(0.0, 0.0),
        vec2f(1.0, 1.0),
        vec2f(1.0, 0.0),
    );
    
    var output: VertexOutput;
    output.position = vec4f(positions[vertexIndex], 0.0, 1.0);
    output.texCoord = texCoords[vertexIndex];
    return output;
}

fn rgb2hsv(rgb: vec3f) -> vec3f {
    let Cmax = max(rgb.r, max(rgb.g, rgb.b));
    let Cmin = min(rgb.r, min(rgb.g, rgb.b));
    let delta = Cmax - Cmin;
    
    var hsv = vec3f(0.0, 0.0, Cmax);
    
    if (Cmax > Cmin) {
        hsv.y = delta / Cmax;
        
        if (rgb.r == Cmax) {
            hsv.x = (rgb.g - rgb.b) / delta;
        } else if (rgb.g == Cmax) {
            hsv.x = 2.0 + (rgb.b - rgb.r) / delta;
        } else {
            hsv.x = 4.0 + (rgb.r - rgb.g) / delta;
        }
        hsv.x = fract(hsv.x / 6.0);
    }
    return hsv;
}

fn chromaKey(color: vec3f, luminance: f32) -> f32 {
    let hsv = rgb2hsv(color);
    let targetHsv = rgb2hsv(uniforms.keyColor);
    
    // Tolerance affects weight multiplication
    let tolFactor = 1.0 + (uniforms.tolerance - 50.0) * 0.02;
    let weights = vec3f(4.0, 1.0, 2.0) * tolFactor;
    
    // Weighted distance in HSV space
    var diff = targetHsv - hsv;
    
    // Handle hue wraparound (hue is circular 0-1)
    if (abs(diff.x) > 0.5) {
        diff.x = diff.x - sign(diff.x);
    }
    
    let dist = length(weights * diff);
    
    // Transparency affects the slope/threshold
    let slope = 3.0 + (uniforms.transparency - 50.0) * 0.06;
    let offset = 1.5 - (uniforms.transparency - 50.0) * 0.03;
    
    // Base alpha calculation
    var alpha = clamp(slope * dist - offset, 0.0, 1.0);
    
    // Phase 2: Apply Highlight control (affects bright areas)
    let highlightFactor = (uniforms.highlight - 50.0) * 0.02;
    let highlightMask = smoothstep(0.5, 1.0, luminance);
    alpha = alpha - (highlightMask * highlightFactor);
    
    // Phase 2: Apply Shadow control (affects dark areas)
    let shadowFactor = (uniforms.shadow - 50.0) * 0.02;
    let shadowMask = smoothstep(0.5, 0.0, luminance);
    alpha = alpha + (shadowMask * shadowFactor);
    
    // Phase 2: Apply Pedestal (shifts entire alpha range)
    let pedestalShift = uniforms.pedestal * 0.01;
    alpha = alpha + pedestalShift;
    
    // Clamp before matte cleanup
    alpha = clamp(alpha, 0.0, 1.0);
    
    // Phase 5: Apply Contrast and Mid Point (Matte Cleanup)
    if (uniforms.contrast > 1.0) {
        // Normalize mid point to 0-1 range
        let pivot = uniforms.midPoint * 0.01;
        
        // Contrast amount (0-200 -> 0-2+)
        let contrastAmount = uniforms.contrast * 0.01;
        
        // Apply S-curve around pivot point
        if (alpha < pivot) {
            // Below pivot: compress toward black
            let t = alpha / pivot;
            alpha = pivot * pow(t, 1.0 + contrastAmount);
        } else {
            // Above pivot: compress toward white
            let t = (alpha - pivot) / (1.0 - pivot);
            alpha = pivot + (1.0 - pivot) * pow(t, 1.0 / (1.0 + contrastAmount));
        }
    }
    
    return clamp(alpha, 0.0, 1.0);
}

fn suppressSpill(color: vec3f, alpha: f32) -> vec3f {
    // Skip if fully transparent or suppression is off
    if (alpha < 0.05 || uniforms.spillSuppression < 1.0) {
        return color;
    }
    
    // Normalize suppression amount (0-100 -> 0-1)
    let suppressionStrength = uniforms.spillSuppression * 0.01;
    
    // Get key color to determine if green or blue screen
    let keyHSV = rgb2hsv(uniforms.keyColor);
    let luma = dot(color, vec3f(0.299, 0.587, 0.114));
    
    var result = color;
    
    // Green screen (hue around 0.25-0.45)
    if (keyHSV.x > 0.2 && keyHSV.x < 0.5) {
        result.g = mix(color.g, luma, suppressionStrength);
    }
    // Blue screen (hue around 0.5-0.7)
    else if (keyHSV.x > 0.45 && keyHSV.x < 0.75) {
        result.b = mix(color.b, luma, suppressionStrength);
    }
    
    // Also apply overall desaturation for extra effect
    result = mix(result, vec3f(luma), suppressionStrength * 0.4);
    
    return result;
}

@fragment
fn fs(input: VertexOutput) -> @location(0) vec4f {
    let videoColor = textureSampleBaseClampToEdge(videoTexture, videoSampler, input.texCoord);
    
    // Calculate luminance
    let luma = dot(videoColor.rgb, vec3f(0.299, 0.587, 0.114));
    
    // Generate alpha matte (simplified - no choke/soften for external texture)
    let alpha = chromaKey(videoColor.rgb, luma);
    
    // Apply spill suppression
    let color = suppressSpill(videoColor.rgb, alpha);
    
    // Output based on mode
    if (uniforms.outputMode == 0) {
        // Composite mode (with alpha)
        return vec4f(color, alpha);
    } else if (uniforms.outputMode == 1) {
        // Alpha channel mode (grayscale)
        return vec4f(vec3f(alpha), 1.0);
    } else if (uniforms.outputMode == 2) {
        // Status mode (color-coded quality)
        var statusColor: vec3f;
        if (alpha > 0.95) {
            statusColor = vec3f(1.0); // White: fully opaque
        } else if (alpha < 0.05) {
            statusColor = vec3f(0.0); // Black: fully transparent
        } else if (alpha > 0.7) {
            statusColor = vec3f(0.3, 0.5, 1.0); // Blue: acceptable
        } else if (alpha > 0.4) {
            statusColor = vec3f(1.0, 1.0, 0.0); // Yellow: marginal
        } else {
            statusColor = vec3f(1.0, 0.0, 0.0); // Red: poor quality
        }
        return vec4f(statusColor, 1.0);
    }
    
    // Default: composite
    return vec4f(color, alpha);
}
