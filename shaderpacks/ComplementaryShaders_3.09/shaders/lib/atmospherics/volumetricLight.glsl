float distx(float dist){
	return (far * (dist - near)) / (dist * (far - near));
}

float getDepth(float depth) {
    return 2.0 * near * far / (far + near - (2.0 * depth - 1.0) * (far - near));
}

vec4 distortShadow(vec4 shadowpos, float distortFactor) {
	shadowpos.xy *= 1.0 / distortFactor;
	shadowpos.z = shadowpos.z * 0.2;
	shadowpos = shadowpos * 0.5 + 0.5;

	return shadowpos;
}

vec4 getShadowSpace(float shadowdepth, vec2 texCoord){
	vec4 viewPos = gbufferProjectionInverse * (vec4(texCoord, shadowdepth, 1.0) * 2.0 - 1.0);
	viewPos /= viewPos.w;

	vec4 wpos = gbufferModelViewInverse * viewPos;
	wpos = shadowModelView * wpos;
	wpos = shadowProjection * wpos;
	wpos /= wpos.w;
	
	float distb = sqrt(wpos.x * wpos.x + wpos.y * wpos.y);
	float distortFactor = 1.0 - shadowMapBias + distb * shadowMapBias;
	wpos = distortShadow(wpos,distortFactor);
	
	#ifdef LIGHTSHAFT_CAUSTICS
	if (isEyeInWater == 1.0) {
	vec3 worldPos = ToWorld(viewPos.xyz);
	vec3 causticpos = worldPos.xyz+cameraPosition.xyz;
	float caustic = getCausticWaves(causticpos.xyz);
	wpos *= caustic;
	}
	#endif
	
	return wpos;
}

//Volumetric light from Robobo1221 (modified)
vec3 getVolumetricRays(float pixeldepth0, float pixeldepth1, vec3 color, float dither) {
	vec3 vl = vec3(0.0);

	#if AA > 1
		dither = fract(dither + frameTimeCounter * 64.0);
	#endif
	
	#ifdef OVERWORLD
		#if LIGHT_SHAFT_MODE == 1
			vec4 viewPos = gbufferProjectionInverse * (vec4(texCoord, pixeldepth0, 1.0) * 2.0 - 1.0);
			viewPos /= viewPos.w;
			vec3 nViewPos = normalize(viewPos.xyz);
			vec3 lightVec = sunVec * (1.0 - 2.0 * float(timeAngle > 0.5325 && timeAngle < 0.9675));
			float cosS = dot(nViewPos, lightVec);
			float visfactor = 0.01 * (3.0 * max(rainStrength - isEyeInWater, 0.0) + 1.0);
			float invvisfactor = 1.0 - visfactor;

			float visibility = clamp(cosS * 0.5 + 0.5, 0.0, 1.0);
			visibility = clamp((visfactor / (1.0 - invvisfactor * visibility) - visfactor) * 1.015 / invvisfactor - 0.015, 0.0, 1.0);

			#ifndef LIGHTSHAFT_CAUSTICS
				float visibilityFactor = 1.0;
			#else
				float visibilityFactor = (1.0 - isEyeInWater);
			#endif

			visibility = mix(1.0, visibility, 0.25 * visibilityFactor + 0.75) * 0.14285;
		#else
			float visibility = 0.055;
			if (isEyeInWater == 1) visibility = 0.19;

			vec4 viewPos = gbufferProjectionInverse * (vec4(texCoord, pixeldepth0, 1.0) * 2.0 - 1.0);
			viewPos /= viewPos.w;
			vec3 nViewPos = normalize(viewPos.xyz);
			vec3 lightVec = sunVec * (1.0 - 2.0 * float(timeAngle > 0.5325 && timeAngle < 0.9675));
			float cosS = dot(nViewPos, lightVec);

			float endurance = LIGHT_SHAFT_ENDURANCE + rainStrength*rainStrength;

			if (endurance < 5.40) {
				if (endurance >= 1.0) visibility *= max((cosS + endurance) / (endurance + 1.0), 0.0);
				else visibility *= pow(max((cosS + 1.0) / 2.0, 0.0), (11.0 - endurance*10.0));
			}
		#endif
		
		if (eyeAltitude < 2.0) visibility *= clamp((eyeAltitude-1.0), 0.0, 1.0);
	#endif
	
	#ifdef END
		float visibility = 0.14285;
	#endif

	if (visibility > 0.0){
		float maxDist = LIGHT_SHAFT_MAX_DISTANCE * (1.5 - isEyeInWater * 0.5);
		
		float depth0 = getDepth(pixeldepth0);
		float depth1 = getDepth(pixeldepth1);
		vec4 worldposition = vec4(0.0);
		
		vec3 watercol = rawWaterColor.rgb * sqrt(rawWaterColor.a / waterAlpha);
		watercol *= watercol * 30;

		#if LIGHT_SHAFT_MODE == 1 || defined END
			float minDistFactor = 5.0 * LIGHT_SHAFT_MIN_DISTANCE;
			float distanceFactor = 0.0;
		#else
			float minDistFactor = 5.0;
			if (isEyeInWater == 0.0) minDistFactor = 12.0 * LIGHT_SHAFT_MIN_DISTANCE;

			float distanceFactor = far / 192.0;
			if (LIGHT_SHAFT_DISTANCE_EXPONENT == 2.0) {
				if (distanceFactor > 1.0) minDistFactor *= distanceFactor * distanceFactor;
				else distanceFactor = 0.0;
			} else {
				if (distanceFactor > 1.0) minDistFactor *= pow(distanceFactor, LIGHT_SHAFT_DISTANCE_EXPONENT);
				else distanceFactor = 0.0;
			}

			float x = abs(texCoord.x - 0.5);
			x = 1.0 - x*x;
			x *= x;
			minDistFactor *= x;
			maxDist *= x;
		#endif
		
		int i_pre = -1 - int(distanceFactor);
		if (isEyeInWater > 0 && i_pre < 0) i_pre = 0;

		for(int i = i_pre; i < 7; i++) {
			float minDist = (i + LIGHT_SHAFT_STEP_ADDITION + dither) * minDistFactor;
			if (isEyeInWater == 1) minDist = (exp2(i + dither) - 0.9) * minDistFactor;
			float breakFactor = 0.0;

			//if (depth0 >= far*0.9999) break;
			if (minDist >= maxDist) breakFactor = 1.0;

			if (isEyeInWater + LIGHT_SHAFT_BREAK > 0.0 && breakFactor > 0.5) break;

			if (depth1 < minDist || (depth0 < minDist && color == vec3(0.0))) break;

			worldposition = getShadowSpace(distx(minDist), texCoord.st);
			//worldposition.z += 0.00002;

			if (length(worldposition.xy * 2.0 - 1.0) < 1.0){
				vec3 sample = vec3(shadow2D(shadowtex0, worldposition.xyz).z);
				
				vec3 colsample = vec3(0.0);
				#ifdef SHADOW_COLOR
					if (sample.r < 0.9){
						float testsample = shadow2D(shadowtex1, worldposition.xyz).z;
						if (testsample > 0.9){
							colsample = texture2D(shadowcolor0, worldposition.xy).rgb;
							colsample *= colsample;
							sample = colsample * (1.0 - sample) + sample;
						}
					}
				#endif
				if (depth0 < minDist) sample *= color;

				#if LIGHT_SHAFT_MODE == 1 || defined END
					if (isEyeInWater == 1.0) sample *= watercol;
					vl += sample;
				#else
					if (isEyeInWater == 1.0) {
						sample *= watercol;
						float sampleFactor = sqrt(minDist / maxDist);
						vl += sample * sampleFactor;
					}
					if (isEyeInWater == 0.0) {
						float sampleFactor = (minDist / maxDist);
						if (!(LIGHT_SHAFT_SAMPLE_DISTRIBUTION == 1.0)) sampleFactor = pow(sampleFactor, LIGHT_SHAFT_SAMPLE_DISTRIBUTION);
						sampleFactor = pow(sampleFactor, 1.0 + sunVisibility * (0.5 - rainStrength));
						vl += sample * sampleFactor * LIGHT_SHAFT_SAMPLE_INTENSITY;
					}
				#endif
			} else {
				vl += 1.0;
			}
			if (breakFactor > 0.5) break;
		}
		vl = sqrt(vl * visibility);
	}
	
	return vl;
}