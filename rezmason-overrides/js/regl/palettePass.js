import colorToRGB from "../colorToRGB.js";
import { loadText, make1DTexture, makePassFBO, makePass } from "./utils.js";

// Maps the brightness of the rendered rain and bloom to colors
// in a 1D gradient palette texture generated from the passed-in color sequence

// This shader introduces noise into the renders, to avoid banding

const makePalette = (regl, entries) => {
	const PALETTE_SIZE = 2048;
	const paletteColors = Array(PALETTE_SIZE);

	// Convert HSL gradient into sorted RGB gradient, capping the ends
	const sortedEntries = entries
		.slice()
		.sort((e1, e2) => e1.at - e2.at)
		.map((entry) => ({
			rgb: colorToRGB(entry.color),
			arrayIndex: Math.floor(Math.max(Math.min(1, entry.at), 0) * (PALETTE_SIZE - 1)),
		}));
	sortedEntries.unshift({ rgb: sortedEntries[0].rgb, arrayIndex: 0 });
	sortedEntries.push({
		rgb: sortedEntries[sortedEntries.length - 1].rgb,
		arrayIndex: PALETTE_SIZE - 1,
	});

	// Interpolate between the sorted RGB entries to generate
	// the palette texture data
	sortedEntries.forEach((entry, index) => {
		paletteColors[entry.arrayIndex] = entry.rgb.slice();
		if (index + 1 < sortedEntries.length) {
			const nextEntry = sortedEntries[index + 1];
			const diff = nextEntry.arrayIndex - entry.arrayIndex;
			for (let i = 0; i < diff; i++) {
				const ratio = i / diff;
				paletteColors[entry.arrayIndex + i] = [
					entry.rgb[0] * (1 - ratio) + nextEntry.rgb[0] * ratio,
					entry.rgb[1] * (1 - ratio) + nextEntry.rgb[1] * ratio,
					entry.rgb[2] * (1 - ratio) + nextEntry.rgb[2] * ratio,
				];
			}
		}
	});

	return make1DTexture(
		regl,
		paletteColors.map((rgb) => [...rgb, 1])
	);
};

// The rendered texture's values are mapped to colors in a palette texture.
// A little noise is introduced, to hide the banding that appears
// in subtle gradients. The noise is also time-driven, so its grain
// won't persist across subsequent frames. This is a safe trick
// in screen space.

export default ({ regl, config }, inputs) => {
	const output = makePassFBO(regl, config.useHalfFloat);
	const paletteTex = makePalette(regl, config.palette);
	const { backgroundColor, cursorColor, glintColor, cursorIntensity, glintIntensity, ditherMagnitude, bgFadeDelay, bgFadeDuration, glitchStrength } = config;

	const palettePassFrag = loadText("shaders/glsl/palettePass.frag.glsl");

	// Optional screen capture injected by MatrixScreensaver.swift for reality-glitch intro
	const captureTex = regl.texture({
		width: 1,
		height: 1,
		data: [0, 0, 0, 0],
		mag: "linear",
		min: "linear",
		wrap: "clamp",
	});
	let hasCapture = false;
	let captureFreed = false;
	const captureFadeEnd = (bgFadeDelay || 0) + (bgFadeDuration || 0);
	if (typeof window !== "undefined" && window.__matrixCapture && captureFadeEnd > 0) {
		const dataURL = window.__matrixCapture;
		window.__matrixCapture = null;
		const img = new Image();
		img.src = dataURL;
		img.decode()
			.then(() => {
				if (!captureFreed) {
					captureTex({
						data: img,
						flipY: true,
						mag: "linear",
						min: "linear",
						wrap: "clamp",
					});
					hasCapture = true;
				}
			})
			.catch(() => {});
	}

	const render = regl({
		frag: regl.prop("frag"),

		uniforms: {
			backgroundColor: colorToRGB(backgroundColor),
			cursorColor: colorToRGB(cursorColor),
			glintColor: colorToRGB(glintColor),
			cursorIntensity,
			glintIntensity,
			ditherMagnitude,
			bgFadeDelay,
			bgFadeDuration,
			glitchStrength,
			hasCapture: () => hasCapture,
			captureTex,
			tex: inputs.primary,
			bloomTex: inputs.bloom,
			paletteTex,
		},
		framebuffer: output,
	});

	return makePass(
		{
			primary: output,
		},
		palettePassFrag.loaded,
		(w, h) => output.resize(w, h),
		(shouldRender) => {
			if (hasCapture && !captureFreed && regl.now() > captureFadeEnd + 1.0) {
				captureTex({ width: 1, height: 1, data: [0, 0, 0, 0] });
				hasCapture = false;
				captureFreed = true;
			}
			if (shouldRender) {
				render({ frag: palettePassFrag.text() });
			}
		}
	);
};
