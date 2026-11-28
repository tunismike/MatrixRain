precision mediump float;
#define PI 3.14159265359

uniform sampler2D tex;
uniform sampler2D bloomTex;
uniform sampler2D paletteTex;
uniform sampler2D captureTex;
uniform bool hasCapture;
uniform float ditherMagnitude;
uniform float time;
uniform float bgFadeDelay, bgFadeDuration, glitchStrength;
uniform vec3 backgroundColor, cursorColor, glintColor;
uniform float cursorIntensity, glintIntensity;
varying vec2 vUV;

highp float rand( const in vec2 uv, const in float t ) {
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c + t);
}

highp float hash11(float p) {
	return fract(sin(p * 127.1 + 311.7) * 43758.5453123);
}

highp float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec4 getBrightness(vec2 uv) {
	vec4 primary = texture2D(tex, uv);
	vec4 bloom = texture2D(bloomTex, uv);
	return primary + bloom;
}

void main() {
	vec4 brightness = getBrightness(vUV);

	// Dither: subtract a random value from the brightness
	brightness -= rand( gl_FragCoord.xy, time ) * ditherMagnitude / 3.0;

	// Map the brightness to a position in the palette texture
	vec3 rainColor =
		texture2D( paletteTex, vec2(brightness.r, 0.0)).rgb
			+ min(cursorColor * cursorIntensity * brightness.g, vec3(1.0))
			+ min(glintColor * glintIntensity * brightness.b, vec3(1.0))
			+ backgroundColor;

	float bgAlpha = 1.0;
	if (bgFadeDuration > 0.0) {
		bgAlpha = smoothstep(bgFadeDelay, bgFadeDelay + bgFadeDuration, time);
	} else if (bgFadeDelay > 0.0) {
		bgAlpha = step(bgFadeDelay, time);
	}

	float rainLum = max(rainColor.r, max(rainColor.g, rainColor.b));
	float rainAlpha = clamp(rainLum * 1.8, 0.0, 1.0);

	// Act 1: Gradual reality "breakdown" (spaced-out eerie hiccups -> escalating failure)
	// Act 2: Crisp CRT power-collapse to pure black
	// Act 3: Matrix rain drops cleanly out of the dead black screen
	if (hasCapture && bgFadeDuration > 0.0 && time < bgFadeDelay + bgFadeDuration) {
		float g = max(0.0, glitchStrength);
		float p = clamp((time - bgFadeDelay) / bgFadeDuration, 0.0, 1.0);

		// Brief calm beat before breakdown begins
		if (p <= 0.0) {
			vec3 clean = texture2D(captureTex, vUV).rgb;
			gl_FragColor = vec4(clean * (1.0 - rainAlpha) + rainColor, 1.0);
			return;
		}

		// Nonlinear escalation curve: gentle & eerie early, intense near p = 0.89
		float linRamp = smoothstep(0.0, 0.89, p);
		float ramp = linRamp * linRamp * (0.35 + 0.65 * linRamp);

		// Snappy discrete glitch beats with genuine calm gaps early on
		float beatFast = floor(time * 15.0);
		float beatSlow = floor(time * 4.0);
		float burstGate = step(1.0 - (0.14 + 0.74 * linRamp), hash11(beatFast + beatSlow * 7.3));
		float majorBurst = step(1.0 - (0.07 + 0.60 * ramp), hash11(beatSlow * 19.1));
		float burst = g * (0.18 + 0.82 * ramp) * max(burstGate * 0.65, majorBurst);

		// Act 2 (p = 0.89 -> 1.0, ~0.7s): Violent old-CRT power-cut snap with white flash
		//   Stage A (0.89 -> 0.922): vertical deflection dies -> violent slam to razor white line
		//   Stage B (0.922 -> 0.962): horizontal line whips inward to blazing white center dot
		//   Stage C (0.962 -> 1.000): hot white phosphor spark cools and snaps out to dead black
		float vT = clamp((p - 0.89) / 0.032, 0.0, 1.0);
		float vSnap = 1.0 - pow(1.0 - vT, 3.0);
		float hT = clamp((p - 0.922) / 0.040, 0.0, 1.0);
		float hSnap = hT * hT * (3.0 - 2.0 * hT);
		float dotT = clamp((p - 0.962) / 0.038, 0.0, 1.0);

		float halfH = mix(0.5, 0.0022, vSnap);
		float halfW = mix(0.5, 0.006, hSnap);

		float dy = abs(vUV.y - 0.5);
		float dx = abs(vUV.x - 0.5);

		// Stay 100% full-screen (zero vignette) until the violent slam begins at p = 0.89
		float yMask = vT > 0.0 ? (1.0 - smoothstep(max(0.0, halfH - 0.004), halfH + 0.004, dy)) : 1.0;
		float xMask = hT > 0.0 ? (1.0 - smoothstep(max(0.0, halfW - 0.010), halfW + 0.010, dx)) : 1.0;
		float crtMask = yMask * xMask * (1.0 - smoothstep(0.955, 0.985, p));

		vec2 uv = vec2(
			0.5 + (vUV.x - 0.5) / max(halfW * 2.0, 0.001),
			0.5 + (vUV.y - 0.5) / max(halfH * 2.0, 0.001)
		);

		// Multi-scale horizontal slice tearing (sparing early, violent right before power-cut)
		float slamJolt = vT * (1.0 - hT);
		float coarseBand = floor(uv.y * 18.0);
		float fineBand = floor(uv.y * 92.0);
		float coarseTrig = step(0.72 - 0.38 * linRamp, hash21(vec2(coarseBand, beatFast)));
		float fineTrig = step(0.86 - 0.36 * linRamp, hash21(vec2(fineBand, beatFast + 31.0)));

		float coarseShift = (hash21(vec2(coarseBand, beatFast + 13.7)) - 0.5) * (0.11 * burst + 0.24 * slamJolt) * coarseTrig;
		float fineShift = (hash21(vec2(fineBand, beatFast + 57.3)) - 0.5) * (0.055 * burst + 0.12 * slamJolt) * fineTrig;
		uv.x = clamp(uv.x + coarseShift + fineShift, 0.0, 1.0);

		// Occasional vertical sync jump during late major hits
		float vSlip = (hash11(beatSlow + 41.0) - 0.5) * 0.024 * majorBurst * g * ramp;
		uv.y = clamp(uv.y + vSlip, 0.0, 1.0);

		// RGB chromatic split: zero between early hiccups, sharp pop on bursts & slam
		float split = (0.0015 * ramp + 0.024 * burst + 0.035 * slamJolt) * g;
		vec3 desk;
		desk.r = texture2D(captureTex, vec2(clamp(uv.x + split, 0.0, 1.0), uv.y)).r;
		desk.g = texture2D(captureTex, uv).g;
		desk.b = texture2D(captureTex, vec2(clamp(uv.x - split, 0.0, 1.0), uv.y)).b;

		// Brief signal-dropout blackout flickers in the final third of the breakdown
		float lateRamp = smoothstep(0.50, 0.89, p);
		float dropout = step(0.88 - 0.22 * lateRamp, hash11(beatFast * 3.1 + 7.0)) * lateRamp * (1.0 - vT);
		desk *= (1.0 - 0.72 * dropout);

		// Matrix green CRT phosphor gradually takes over as reality breaks down
		float deskLum = dot(desk, vec3(0.299, 0.587, 0.114));
		vec3 phosphor = vec3(deskLum * 0.10, min(1.0, deskLum * 1.22), deskLum * 0.24);
		float greenShift = clamp(ramp * 0.70 + burst * 0.35, 0.0, 1.0);
		desk = mix(desk, phosphor, greenShift);

		// Crisp horizontal phosphor flash slivers on major hits
		float barFlash = fineTrig * majorBurst * g * ramp * 0.24;
		desk += vec3(0.04, 0.42, 0.10) * barFlash;

		// Electric white overexposure flash right as vertical deflection snaps shut
		float powerSurge = exp(-pow((p - 0.898) / 0.011, 2.0));
		desk = mix(desk, vec3(0.95, 1.0, 0.96), clamp(vSnap * 0.85 + powerSurge * 0.75, 0.0, 1.0));
		desk *= (1.0 + powerSurge * 0.9);

		// Blazing white-hot horizontal CRT beam + electric outer halo during Stages A & B
		float beamActive = smoothstep(0.892, 0.916, p) * (1.0 - smoothstep(0.958, 0.976, p));
		float xExtent = 1.0 - smoothstep(max(0.0, halfW - 0.025), halfW + 0.025, dx);
		float beamCore = exp(-dy / 0.0024) * xExtent * beamActive;
		float beamHalo = exp(-dy / 0.020) * xExtent * beamActive * 0.65;
		vec3 crtBeam = vec3(1.0, 1.0, 1.0) * beamCore * 1.8
			+ vec3(0.55, 1.0, 0.72) * beamHalo;

		// Searing white center pinpoint spark as the line collapses into the center (Stage B -> C)
		float dotActive = smoothstep(0.945, 0.964, p) * (1.0 - smoothstep(0.972, 1.0, p));
		float dotDist = length(vec2(dx * 1.65, dy));
		float dotRadius = mix(0.016, 0.0018, dotT);
		float dotCore = exp(-dotDist / max(dotRadius * 0.35, 0.0008)) * dotActive;
		float dotHalo = exp(-dotDist / max(dotRadius * 2.4, 0.002)) * dotActive * 0.85;
		vec3 dotColor = mix(vec3(1.0, 1.0, 1.0), vec3(0.45, 1.0, 0.62), dotT * 0.75);
		vec3 crtDot = vec3(1.0, 1.0, 1.0) * dotCore * 2.0 + dotColor * dotHalo;

		// Subtle full-screen white electrical discharge flicker at the instant of snap
		vec3 snapFlash = vec3(0.85, 1.0, 0.90) * powerSurge * 0.32 * (1.0 - vSnap * 0.7);

		vec3 crtComposite = clamp(desk * crtMask + crtBeam + crtDot + snapFlash, 0.0, 1.0);
		vec3 finalColor = crtComposite * (1.0 - rainAlpha) + rainColor;
		gl_FragColor = vec4(finalColor, 1.0);
		return;
	}

	// Steady state (bit-for-bit identical classic Matrix rain) or transparent fallback
	float alpha = max(bgAlpha, rainAlpha);
	gl_FragColor = vec4(rainColor, alpha);
}
