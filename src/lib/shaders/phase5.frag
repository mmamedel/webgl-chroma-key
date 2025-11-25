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
uniform float u_contrast;
uniform float u_midPoint;
uniform float u_choke;
uniform float u_soften;
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
	
	// Clamp before matte cleanup
	alpha = clamp(alpha, 0.0, 1.0);
	
	// Phase 5: Apply Contrast and Mid Point (Matte Cleanup)
	if (u_contrast > 1.0) {
		// Normalize mid point to 0-1 range
		float pivot = u_midPoint * 0.01;
		
		// Contrast amount (0-200 -> 0-2+)
		// Scale down slightly for smoother curve
		float contrastAmount = u_contrast * 0.01;
		
		// Apply S-curve around pivot point
		if (alpha < pivot) {
			// Below pivot: compress toward black
			float t = alpha / pivot;
			alpha = pivot * pow(t, 1.0 + contrastAmount);
		} else {
			// Above pivot: compress toward white
			float t = (alpha - pivot) / (1.0 - pivot);
			alpha = pivot + (1.0 - pivot) * pow(t, 1.0 / (1.0 + contrastAmount));
		}
	}
	
	// Final clamp
	return clamp(alpha, 0.0, 1.0);
}

// Apply choke (erosion/dilation) by sampling neighborhood
float applyChoke(vec2 uv, float alpha) {
	if (abs(u_choke) < 0.1) return alpha;
	
	// Calculate sample radius (1-3 pixels)
	const int maxRadius = 3;
	vec2 pixelSize = 1.0 / u_resolution;
	
	float result = alpha;
	
	if (u_choke > 0.0) {
		// Positive = erosion (take minimum)
		result = 1.0;
		for (int y = -maxRadius; y <= maxRadius; y++) {
			for (int x = -maxRadius; x <= maxRadius; x++) {
				// Skip samples outside desired radius
				float dist = length(vec2(float(x), float(y)));
				if (dist > abs(u_choke) * 0.15) continue;
				
				vec2 offset = vec2(float(x), float(y)) * pixelSize;
				vec4 sampleColor = texture2D(u_video, uv + offset);
				float sampleLuma = dot(sampleColor.rgb, vec3(0.299, 0.587, 0.114));
				float sampleAlpha = chromaKey(sampleColor.rgb, sampleLuma);
				result = min(result, sampleAlpha);
			}
		}
	} else {
		// Negative = dilation (take maximum)
		result = 0.0;
		for (int y = -maxRadius; y <= maxRadius; y++) {
			for (int x = -maxRadius; x <= maxRadius; x++) {
				// Skip samples outside desired radius
				float dist = length(vec2(float(x), float(y)));
				if (dist > abs(u_choke) * 0.15) continue;
				
				vec2 offset = vec2(float(x), float(y)) * pixelSize;
				vec4 sampleColor = texture2D(u_video, uv + offset);
				float sampleLuma = dot(sampleColor.rgb, vec3(0.299, 0.587, 0.114));
				float sampleAlpha = chromaKey(sampleColor.rgb, sampleLuma);
				result = max(result, sampleAlpha);
			}
		}
	}
	
	return result;
}

// Apply soften (Gaussian blur) to alpha
float applySoften(vec2 uv, float alpha) {
	if (u_soften < 0.1) return alpha;
	
	// Fixed maximum radius for loop
	const int maxRadius = 4;
	vec2 pixelSize = 1.0 / u_resolution;
	
	float sum = 0.0;
	float weight = 0.0;
	
	// Simple box blur (could be Gaussian for better quality)
	for (int y = -maxRadius; y <= maxRadius; y++) {
		for (int x = -maxRadius; x <= maxRadius; x++) {
			// Skip samples outside desired radius
			float dist = length(vec2(float(x), float(y)));
			float desiredRadius = u_soften * 0.2;
			if (dist > desiredRadius) continue;
			
			vec2 offset = vec2(float(x), float(y)) * pixelSize;
			float w = 1.0 / (1.0 + dist); // Simple falloff
			
			vec4 sampleColor = texture2D(u_video, uv + offset);
			float sampleLuma = dot(sampleColor.rgb, vec3(0.299, 0.587, 0.114));
			float sampleAlpha = chromaKey(sampleColor.rgb, sampleLuma);
			
			sum += sampleAlpha * w;
			weight += w;
		}
	}
	
	return sum / weight;
}

vec3 suppressSpill(vec3 color, float alpha) {
	// Skip if fully transparent or suppression is off
	if (alpha < 0.05 || u_spillSuppression < 1.0) return color;
	
	// Normalize suppression amount (0-100 -> 0-1)
	float suppressionStrength = u_spillSuppression * 0.01;
	
	// Get key color to determine if green or blue screen
	vec3 keyHSV = rgb2hsv(u_keyColor);
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	
	vec3 result = color;
	
	// Green screen (hue around 0.25-0.45)
	if (keyHSV.x > 0.2 && keyHSV.x < 0.5) {
		// Aggressively reduce green channel
		result.g = mix(color.g, luma, suppressionStrength);
	}
	// Blue screen (hue around 0.5-0.7)
	else if (keyHSV.x > 0.45 && keyHSV.x < 0.75) {
		// Aggressively reduce blue channel
		result.b = mix(color.b, luma, suppressionStrength);
	}
	
	// Also apply overall desaturation for extra effect
	result = mix(result, vec3(luma), suppressionStrength * 0.4);
	
	return result;
}

void main() {
	vec2 uv = v_texCoord;
	vec4 videoColor = texture2D(u_video, uv);
	
	// Calculate luminance
	float luma = dot(videoColor.rgb, vec3(0.299, 0.587, 0.114));
	
	// Generate alpha matte
	float alpha = chromaKey(videoColor.rgb, luma);
	
	// Phase 5: Apply Choke (if enabled)
	if (abs(u_choke) > 0.1) {
		alpha = applyChoke(uv, alpha);
	}
	
	// Phase 5: Apply Soften (if enabled)
	if (u_soften > 0.1) {
		alpha = applySoften(uv, alpha);
	}
	
	// Apply spill suppression (Phase 4)
	vec3 color = suppressSpill(videoColor.rgb, alpha);
	
	// Output based on mode
	if (u_outputMode == 0) {
		// Composite mode (with alpha)
		gl_FragColor = vec4(color, alpha);
	} else if (u_outputMode == 1) {
		// Alpha channel mode (grayscale)
		gl_FragColor = vec4(vec3(alpha), 1.0);
	} else if (u_outputMode == 2) {
		// Status mode (color-coded quality)
		vec3 statusColor;
		if (alpha > 0.95) {
			statusColor = vec3(1.0); // White: fully opaque (GOOD)
		} else if (alpha < 0.05) {
			statusColor = vec3(0.0); // Black: fully transparent (GOOD)
		} else if (alpha > 0.7) {
			statusColor = vec3(0.3, 0.5, 1.0); // Blue: acceptable
		} else if (alpha > 0.4) {
			statusColor = vec3(1.0, 1.0, 0.0); // Yellow: marginal
		} else {
			statusColor = vec3(1.0, 0.0, 0.0); // Red: poor quality
		}
		gl_FragColor = vec4(statusColor, 1.0);
	} else {
		// Default: composite
		gl_FragColor = vec4(color, alpha);
	}
}
