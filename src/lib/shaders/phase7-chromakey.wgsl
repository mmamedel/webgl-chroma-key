// Phase 7: Multi-pass WebGPU Chroma Key Shader
// Pass 1: Chroma key with regular texture_2d (allows neighbor sampling in later passes)

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

@group(0) @binding(0) var textureSampler: sampler;
@group(0) @binding(1) var videoTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

@vertex
fn vs(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    let positions = array<vec2f, 6>(
        vec2f(-1.0, -1.0),
        vec2f( 1.0, -1.0),
        vec2f(-1.0,  1.0),
        vec2f(-1.0,  1.0),
        vec2f( 1.0, -1.0),
        vec2f( 1.0,  1.0),
    );
    
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
    
    let tolFactor = 1.0 + (uniforms.tolerance - 50.0) * 0.02;
    let weights = vec3f(4.0, 1.0, 2.0) * tolFactor;
    
    var diff = targetHsv - hsv;
    
    if (abs(diff.x) > 0.5) {
        diff.x = diff.x - sign(diff.x);
    }
    
    let dist = length(weights * diff);
    
    let slope = 3.0 + (uniforms.transparency - 50.0) * 0.06;
    let offset = 1.5 - (uniforms.transparency - 50.0) * 0.03;
    
    var alpha = clamp(slope * dist - offset, 0.0, 1.0);
    
    let highlightFactor = (uniforms.highlight - 50.0) * 0.02;
    let highlightMask = smoothstep(0.5, 1.0, luminance);
    alpha = alpha - (highlightMask * highlightFactor);
    
    let shadowFactor = (uniforms.shadow - 50.0) * 0.02;
    let shadowMask = smoothstep(0.5, 0.0, luminance);
    alpha = alpha + (shadowMask * shadowFactor);
    
    let pedestalShift = uniforms.pedestal * 0.01;
    alpha = alpha + pedestalShift;
    
    alpha = clamp(alpha, 0.0, 1.0);
    
    if (uniforms.contrast > 1.0) {
        let pivot = uniforms.midPoint * 0.01;
        let contrastAmount = uniforms.contrast * 0.01;
        
        if (alpha < pivot) {
            let t = alpha / pivot;
            alpha = pivot * pow(t, 1.0 + contrastAmount);
        } else {
            let t = (alpha - pivot) / (1.0 - pivot);
            alpha = pivot + (1.0 - pivot) * pow(t, 1.0 / (1.0 + contrastAmount));
        }
    }
    
    return clamp(alpha, 0.0, 1.0);
}

fn suppressSpill(color: vec3f, alpha: f32) -> vec3f {
    if (alpha < 0.05 || uniforms.spillSuppression < 1.0) {
        return color;
    }
    
    let suppressionStrength = uniforms.spillSuppression * 0.01;
    let keyHSV = rgb2hsv(uniforms.keyColor);
    let luma = dot(color, vec3f(0.299, 0.587, 0.114));
    
    var result = color;
    
    if (keyHSV.x > 0.2 && keyHSV.x < 0.5) {
        result.g = mix(color.g, luma, suppressionStrength);
    } else if (keyHSV.x > 0.45 && keyHSV.x < 0.75) {
        result.b = mix(color.b, luma, suppressionStrength);
    }
    
    result = mix(result, vec3f(luma), suppressionStrength * 0.4);
    
    return result;
}

@fragment
fn fs(input: VertexOutput) -> @location(0) vec4f {
    let videoColor = textureSample(videoTexture, textureSampler, input.texCoord);
    let luma = dot(videoColor.rgb, vec3f(0.299, 0.587, 0.114));
    let alpha = chromaKey(videoColor.rgb, luma);
    let color = suppressSpill(videoColor.rgb, alpha);
    
    // Output RGBA with alpha in the alpha channel for next passes
    return vec4f(color, alpha);
}
