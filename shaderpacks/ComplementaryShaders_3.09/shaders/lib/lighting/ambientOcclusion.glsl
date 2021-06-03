vec2 OffsetDist(float x, int s){
	float n = fract(x * 1.414) * 3.1415;
    return vec2(cos(n), sin(n)) * x / s;
}

float AmbientOcclusion(sampler2D depth, float dither){
	float ao = 0.0;

	#if AA > 1
    dither = fract(frameTimeCounter * 4.0 + dither);
	#endif
	
	int samples = AO_QUALITY;
	
	float d = texture2D(depth, texCoord).r;
	float hand = float(d < 0.56);
	d = GetLinearDepth(d);
	
	float sd = 0.0, angle = 0.0, dist = 0.0;
	float fovScale = gbufferProjection[1][1] / 2.74747742;
	float distScale = max((far - near) * d + near, 6.0);
	vec2 scale = 0.4 * vec2(1.0, aspectRatio) * fovScale / distScale;

	for(int i = 1; i <= samples; i++) {
		vec2 offset = OffsetDist(i + dither, samples) * scale;

		sd = GetLinearDepth(texture2D(depth, texCoord + offset).r);
		float sample = (far - near) * (d - sd) * 2.0;
		if (hand > 0.5) sample *= 1024.0;
		angle = clamp(0.5 - sample, 0.0, 1.0);
		dist = clamp(0.5 * sample - 1.0, 0.0, 1.0);

		sd = GetLinearDepth(texture2D(depth, texCoord - offset).r);
		sample = (far - near) * (d - sd) * 2.0;
		if (hand > 0.5) sample *= 1024.0;
		angle += clamp(0.5 - sample, 0.0, 1.0);
		dist += clamp(0.5 * sample - 1.0, 0.0, 1.0);
		
		ao += clamp(angle + dist, 0.0, 1.0);
	}
	ao /= samples;
	
	return ao;
}