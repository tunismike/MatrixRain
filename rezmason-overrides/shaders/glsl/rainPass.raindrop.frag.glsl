precision highp float;

// This shader is the star of the show.
// It writes falling rain to the channels of a data texture:
// 		R: raindrop brightness
// 		G: whether the cell is a "cursor"
// 		B: whether the cell is "activated" — to animate the intro
// 		A: unused

// Listen.
// I understand if this shader looks confusing. Please don't be discouraged!
// It's just a handful of sine and fract functions. Try commenting parts out to learn
// how the different steps combine to produce the result. And feel free to reach out. -RM

#define PI 3.14159265359
#define SQRT_2 1.4142135623730951
#define SQRT_5 2.23606797749979

uniform sampler2D previousRaindropState, introState;
uniform float numColumns, numRows;
uniform float time, tick;
uniform float animationSpeed, fallSpeed;

uniform bool loops, skipIntro;
uniform float brightnessDecay;
uniform float raindropLength;
uniform float speedSpread, speedVariance, driftRate;

// Helper functions for generating randomness, borrowed from elsewhere

highp float randomFloat( const in vec2 uv ) {
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c);
}

vec2 randomVec2( const in vec2 uv ) {
	return fract(vec2(sin(uv.x * 591.32 + uv.y * 154.077), cos(uv.x * 391.32 + uv.y * 49.077)));
}

float wobble(float x) {
	return x + 0.3 * sin(SQRT_2 * x) + 0.2 * sin(SQRT_5 * x);
}

// Per-column speed drift. A column has no state here, so instead of storing a
// velocity and nudging it (what the canvas version does), we warp TIME by a
// function whose derivative is guaranteed positive - the column can slow down
// and speed up but can never run backwards.
//   d/dt = 1 + speedVariance * (cos.. + 0.60 cos.. + 0.35 cos..) / 1.95
// and the bracket is bounded by 1.95, so the rate stays in
// [1 - speedVariance, 1 + speedVariance]. Keep speedVariance < 1.
// The three frequencies are mutually incommensurate so it never visibly loops.
float speedWarp(float t, float phase) {
	float w1 = 1.1 * driftRate, w2 = 2.3 * driftRate, w3 = 4.7 * driftRate;
	return t + speedVariance * (
		  sin(w1 * t + phase) / w1
		+ 0.60 * sin(w2 * t + 1.7 * phase) / w2
		+ 0.35 * sin(w3 * t + 2.9 * phase) / w3
	) / 1.95;
}

// This is the code rain's key underlying concept.
// It's why glyphs that share a column are lit simultaneously, and are brighter toward the bottom.
// It's also why those bright areas are truncated into raindrops.
float getRainBrightness(float simTime, vec2 glyphPos) {
	float columnTimeOffset = randomFloat(vec2(glyphPos.x, 0.)) * 1000.;
	// speedSpread 0.5 reproduces the original [0.5, 1.0] spread exactly.
	float columnSpeedOffset = randomFloat(vec2(glyphPos.x + 0.1, 0.)) * speedSpread + (1. - speedSpread);
	float columnPhase = randomFloat(vec2(glyphPos.x + 0.2, 0.)) * 6.2831853;
	float driftTime = speedWarp(simTime, columnPhase);
	if (loops) {
		columnSpeedOffset = 0.5;
		driftTime = simTime;              // drift would break the seamless loop
	}
	float columnTime = columnTimeOffset + driftTime * fallSpeed * columnSpeedOffset;
	float rainTime = (glyphPos.y * 0.01 + columnTime) / raindropLength;
	if (!loops) {
		rainTime = wobble(rainTime);
	}
	return 1.0 - fract(rainTime);
}

// Main function

vec4 computeResult(float simTime, bool isFirstFrame, vec2 glyphPos, vec4 previous, vec4 intro) {
	float brightness = getRainBrightness(simTime, glyphPos);
	float brightnessBelow = getRainBrightness(simTime, glyphPos + vec2(0., -1.));

	float introProgress = intro.r - (1. - glyphPos.y / numRows);
	float introProgressBelow = intro.r - (1. - (glyphPos.y - 1.) / numRows);

	bool activated = bool(previous.b) || skipIntro || introProgress > 0.;
	bool activatedBelow = skipIntro || introProgressBelow > 0.;

	bool cursor = brightness > brightnessBelow || (activated && !activatedBelow);

	// Blend the glyph's brightness with its previous brightness, so it winks on and off organically
	if (!isFirstFrame) {
		float previousBrightness = previous.r;
		brightness = mix(previousBrightness, brightness, brightnessDecay);
	}

	vec4 result = vec4(brightness, cursor, activated, introProgress);
	return result;
}

void main()	{
	float simTime = time * animationSpeed;
	bool isFirstFrame = tick <= 1.;
	vec2 glyphPos = gl_FragCoord.xy;
	vec2 screenPos = glyphPos / vec2(numColumns, numRows);
	vec4 previous = texture2D( previousRaindropState, screenPos );
	vec4 intro = texture2D( introState, vec2(screenPos.x, 0.) );
	gl_FragColor = computeResult(simTime, isFirstFrame, glyphPos, previous, intro);
}
