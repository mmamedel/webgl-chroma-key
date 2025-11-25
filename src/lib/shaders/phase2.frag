precision mediump float;

uniform sampler2D u_video;
uniform sampler2D u_background;
uniform vec2 u_resolution;
uniform vec3 u_keyColor;
uniform float u_transparency;
uniform float u_tolerance;
uniform float u_highlight;
uniform float u_shadow;
uniform float u_pedestal;
uniform int u_outputMode;

varying vec2 v_texCoord;

vec3 rgb2hsv(vec3 rgb) {
	float Cmax = max(rgb.r, max(rgb.g, rgb.b));
	float Cmin = min(rgb.r, min(rgb.g, rgb.b));
	float delta = Cmax - Cmin;

	vec3 hsv = vec3(0., 0., Cmax);
	
	if (Cmax > Cmin) {
		hsv.y = delta / Cmax;

		if (rgb.r == Cmax)
			hsv.x = (rgb.g - rgb.b) / delta;
		else {
			if (rgb.g == Cmax)
				hsv.x = 2. + (rgb.b - rgb.r) / delta;
			else
				hsv.x = 4. + (rgb.r - rgb.g) / delta;
		}
		hsv.x = fract(hsv.x / 6.);
	}
	return hsv;
}

float chromaKey(vec3 color, float luminance) {
	vec3 hsv = rgb2hsv(color);
	vec3 target = rgb2hsv(u_keyColor);
	
	// Tolerance affects weight multiplication
	float tolFactor = 1.0 + (u_tolerance - 50.0) * 0.02;
	vec3 weights = vec3(4.0, 1.0, 2.0) * tolFactor;
	
	// Weighted distance in HSV space
	vec3 diff = target - hsv;
	
	// Handle hue wraparound (hue is circular 0-1)
	if (abs(diff.x) > 0.5) {
		diff.x = diff.x - sign(diff.x);
	}
	
	float dist = length(weights * diff);
	
	// Transparency affects the slope/threshold
	float slope = 3.0 + (u_transparency - 50.0) * 0.06;
	float offset = 1.5 - (u_transparency - 50.0) * 0.03;
	
	// Base alpha calculation
	float alpha = clamp(slope * dist - offset, 0.0, 1.0);
	
	// Phase 2: Apply Highlight control (affects bright areas)
	// Highlight range: 0-100, default 50 (no effect)
	// Higher values make bright areas more transparent
	float highlightFactor = (u_highlight - 50.0) * 0.02; // -1.0 to 1.0
	float highlightMask = smoothstep(0.5, 1.0, luminance);
	alpha = alpha - (highlightMask * highlightFactor);
	
	// Phase 2: Apply Shadow control (affects dark areas)
	// Shadow range: 0-100, default 50 (no effect)
	// Higher values make dark areas more opaque
	float shadowFactor = (u_shadow - 50.0) * 0.02; // -1.0 to 1.0
	float shadowMask = smoothstep(0.5, 0.0, luminance);
	alpha = alpha + (shadowMask * shadowFactor);
	
	// Phase 2: Apply Pedestal (shifts entire alpha range)
	// Pedestal range: 0-100, default 0 (no shift)
	// Positive values make everything more opaque
	float pedestalShift = (u_pedestal - 0.0) * 0.01; // 0.0 to 1.0
	alpha = alpha + pedestalShift;
	
	// Clamp final alpha
	return clamp(alpha, 0.0, 1.0);
}

vec3 changeSaturation(vec3 color, float saturation) {
	float luma = dot(vec3(0.213, 0.715, 0.072) * color, vec3(1.));
	return mix(vec3(luma), color, saturation);
}

void main() {
	vec2 uv = v_texCoord;
	
	vec3 color = texture2D(u_video, uv).rgb;
	vec3 bg = texture2D(u_background, vec2(1.0 - uv.x, uv.y)).rgb;
	
	// Calculate luminance for Highlight/Shadow controls
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	
	float alpha = chromaKey(color, luminance);
	
	// Output mode selection
	if (u_outputMode == 1) {
		// Alpha Channel mode (grayscale)
		gl_FragColor = vec4(vec3(alpha), 1.0);
	} else {
		// Composite mode
		// TODO Phase 4: Make spill suppression configurable
		color = changeSaturation(color, 0.5);
		color = mix(bg, color, alpha);
		gl_FragColor = vec4(color, 1.0);
	}
}
