precision mediump float;

uniform sampler2D u_video;
uniform vec2 u_resolution;
uniform vec3 u_keyColor;
uniform float u_transparency;
uniform float u_tolerance;
uniform float u_highlight;
uniform float u_shadow;
uniform float u_pedestal;
uniform float u_spillSuppression;
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
	float highlightFactor = (u_highlight - 50.0) * 0.02;
	float highlightMask = smoothstep(0.5, 1.0, luminance);
	alpha = alpha - (highlightMask * highlightFactor);
	
	// Phase 2: Apply Shadow control (affects dark areas)
	float shadowFactor = (u_shadow - 50.0) * 0.02;
	float shadowMask = smoothstep(0.5, 0.0, luminance);
	alpha = alpha + (shadowMask * shadowFactor);
	
	// Phase 2: Apply Pedestal (shifts entire alpha range)
	float pedestalShift = (u_pedestal - 0.0) * 0.01;
	alpha = alpha + pedestalShift;
	
	// Clamp final alpha
	return clamp(alpha, 0.0, 1.0);
}

// Phase 4: Calculate spill proximity (how close pixel is to key color)
float getSpillProximity(vec3 color) {
	vec3 hsv = rgb2hsv(color);
	vec3 target = rgb2hsv(u_keyColor);
	
	// Use same weighted distance as chromaKey
	vec3 diff = target - hsv;
	
	// Handle hue wraparound
	if (abs(diff.x) > 0.5) {
		diff.x = diff.x - sign(diff.x);
	}
	
	vec3 weights = vec3(4.0, 1.0, 2.0);
	float dist = length(weights * diff);
	
	// Convert distance to proximity (0 = far, 1 = close to key)
	// Use smoothstep for smooth falloff
	return 1.0 - smoothstep(0.0, 2.0, dist);
}

vec3 changeSaturation(vec3 color, float saturation) {
	float luma = dot(vec3(0.213, 0.715, 0.072) * color, vec3(1.));
	return mix(vec3(luma), color, saturation);
}

// Phase 4: Apply targeted spill suppression
vec3 applySpillSuppression(vec3 color, float alpha) {
	// Only apply spill suppression if enabled (spillSuppression > 0)
	if (u_spillSuppression <= 0.0) {
		return color;
	}
	
	// Calculate how close this pixel is to the key color
	float spillProximity = getSpillProximity(color);
	
	// Calculate suppression amount based on:
	// 1. User's spillSuppression setting (0-100)
	// 2. How close pixel is to key color (spillProximity)
	// 3. Alpha value (only affect edges, not fully opaque areas)
	
	// Convert spillSuppression from 0-100 to 0-1
	float suppressionAmount = u_spillSuppression / 100.0;
	
	// Reduce suppression on fully opaque areas (alpha near 1)
	// We want maximum suppression on edges (alpha 0.3-0.9)
	float edgeMask = smoothstep(0.95, 0.7, alpha) * smoothstep(0.0, 0.3, alpha);
	
	// Final suppression: combines user setting, spill proximity, and edge mask
	float finalSuppression = suppressionAmount * spillProximity * edgeMask;
	
	// Apply desaturation based on final suppression amount
	// 0 = keep full saturation, 1 = remove all saturation
	float targetSaturation = 1.0 - finalSuppression;
	
	return changeSaturation(color, targetSaturation);
}

// Phase 3: Status mode color coding
vec3 getStatusColor(float alpha) {
	if (alpha < 0.1) {
		return vec3(0.0, 1.0, 0.0); // Green - fully transparent
	} else if (alpha < 0.3) {
		return mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), (alpha - 0.1) / 0.2);
	} else if (alpha < 0.7) {
		return mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (alpha - 0.3) / 0.4);
	} else if (alpha < 0.9) {
		return mix(vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0), (alpha - 0.7) / 0.2);
	} else {
		return vec3(1.0, 1.0, 1.0); // White - fully opaque
	}
}

void main() {
	vec2 uv = v_texCoord;
	
	vec3 color = texture2D(u_video, uv).rgb;
	
	// Calculate luminance for Highlight/Shadow controls
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	
	float alpha = chromaKey(color, luminance);
	
	// Phase 3: Output mode selection with Status mode
	if (u_outputMode == 1) {
		// Alpha Channel mode (grayscale matte)
		gl_FragColor = vec4(vec3(alpha), 1.0);
	} else if (u_outputMode == 2) {
		// Status mode (color-coded visualization)
		vec3 statusColor = getStatusColor(alpha);
		gl_FragColor = vec4(statusColor, 1.0);
	} else {
		// Composite mode - output with transparency
		// Phase 4: Apply configurable, targeted spill suppression
		color = applySpillSuppression(color, alpha);
		gl_FragColor = vec4(color, alpha);
	}
}
