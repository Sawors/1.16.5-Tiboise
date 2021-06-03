#if defined OVERWORLD || defined END || defined SEVEN
#include "/lib/lighting/shadows.glsl"

vec3 DistortShadow(inout vec3 worldPos, float distortFactor){
	worldPos.xy /= distortFactor;
	worldPos.z *= 0.2;
	return worldPos * 0.5 + 0.5;
}
#endif

void GetLighting(inout vec3 albedo, out vec3 shadow, vec3 viewPos, vec3 worldPos,
                 vec2 lightmap, float smoothLighting, float NdotL, float quarterNdotU,
                 float parallaxShadow, float emissive, float foliage, float mat, float leaves) {

	vec3 fullShadow = vec3(0.0);

    #if defined OVERWORLD || defined END || defined SEVEN
		vec3 shadowPos = ToShadow(worldPos);

		float distb = sqrt(shadowPos.x * shadowPos.x + shadowPos.y * shadowPos.y);
		float distortFactor = distb * shadowMapBias + (1.0 - shadowMapBias);
		shadowPos = DistortShadow(shadowPos, distortFactor);

		float doShadow = float(shadowPos.x > 0.0 && shadowPos.x < 1.0 &&
							shadowPos.y > 0.0 && shadowPos.y < 1.0);

		#if defined OVERWORLD || defined SEVEN
			#ifdef SUNLIGHT_LEAK_FIX
				doShadow *= float(lightmap.y > 0.001);
			#endif
		#endif
		
		if ((NdotL > 0.0 || foliage > 0.5)){
			if (doShadow > 0.5){
				float NdotLm = NdotL * 0.99 + 0.01;
				
				float biasFactor = sqrt(1.0 - NdotLm * NdotLm) / NdotLm;
				float distortBias = distortFactor * shadowDistance / 256.0;
				distortBias *= 8.0 * distortBias;
				
				float bias = (distortBias * biasFactor + 0.05) / shadowMapResolution;
				float offset = 1.0 / shadowMapResolution;

				if (foliage > 0.5){
					bias = 0.0002;
					offset = 0.002;
				}
				
				shadow = GetShadow(shadowPos, bias, offset);

			} else shadow = vec3(lightmap.y);
		}
		shadow *= parallaxShadow;

		if (leaves > 0.5) {
			foliage *= SCATTERING_LEAVES;
		} else {
			foliage *= SCATTERING_FOLIAGE;
		}
		
		fullShadow = shadow * max(NdotL, foliage * (1.0 - rainStrength * 0.80));
		
		#ifdef OVERWORLD
			float shadowMult = 1.0 * (1.0 - 0.9 * rainStrength);
			
			#ifdef LIGHT_JUMP_FIX
				float shadowTime = worldTime;
				shadowTime -= floor(shadowTime / 24000) * 24000;
				if (shadowTime < 12800) {
					shadowTime = clamp((12800 - shadowTime) / 400, 0.0, 1.0);
				} else if (shadowTime < 23200) {
					if (shadowTime < 18000) shadowTime = clamp((shadowTime - 12800) / 400, 0.0, 1.0);
					if (shadowTime > 18000) shadowTime = clamp((23200 - shadowTime) / 400, 0.0, 1.0);
				} else {
					shadowTime = clamp((shadowTime - 23200) / 400, 0.0, 1.0);
				}
				shadowMult *= clamp(shadowTime*shadowTime, 0.0, 1.0);
			#endif
			
			#ifndef SUNLIGHT_LEAK_FIX
				ambientCol *= pow(lightmap.y, 2.5);
			#endif
			
			vec3 lightingCol = pow(lightCol, vec3(1.0 + sunVisibility));
			vec3 sceneLighting = mix(ambientCol, lightingCol, fullShadow * shadowMult);
			
			#ifdef SUNLIGHT_LEAK_FIX
				sceneLighting *= pow(lightmap.y, 2.5);
			#endif
		#endif

		#ifdef END
			vec3 sceneLighting = endCol * (0.1 * fullShadow + 0.07);
		#endif
		
		#if defined SEVEN && !defined SEVEN_2
			sceneLighting = vec3(0.005, 0.006, 0.018) * 133 * (0.3 * fullShadow + 0.025);
		#endif
		#ifdef SEVEN_2
			vec3 sceneLighting = vec3(0.005, 0.006, 0.018) * 33 * (1.0 * fullShadow + 0.025);
		#endif
		#if defined SEVEN || defined SEVEN_2
			sceneLighting *= lightmap.y * lightmap.y;
		#endif
		

		if (foliage > 0.5){
			float VdotL = clamp(dot(normalize(viewPos.xyz), lightVec), 0.0, 1.0);
			float subsurface = pow(VdotL, 25.0);
			sceneLighting *= 3.0 * fullShadow * subsurface + 1.0;
		}
    #else
		#ifdef NETHER
			#if MC_VERSION <= 11600
			#else
				if (quarterNdotU < 0.5625) quarterNdotU = 0.5625 + (0.4 - quarterNdotU * 0.7111111111111111);
			#endif
		
			vec3 sceneLighting = netherCol * (1 - pow(length(fogColor / 3), 0.25)) * NETHER_I * (screenBrightness*0.25 + 0.5);
		#else
			vec3 sceneLighting = vec3(0.0);
		#endif
    #endif
	
	#if !defined COMPATIBILITY_MODE && defined GBUFFERS_WATER
		if (mat > 2.98 && mat < 3.02) sceneLighting *= 0.0;
	#endif

	#if !defined COMPATIBILITY_MODE && defined ADVANCED_MATERIALS
		float newLightmap  = pow(lightmap.x, 10.0) * 5 + max((lightmap.x - 0.05) * 0.925, 0.0) * (screenBrightness*0.25 + 0.9);
	#else
		if (lightmap.x > 0.5) lightmap.x = smoothstep(0.0, 1.0, lightmap.x);
		float newLightmap  = pow(lightmap.x, 10.0) * 1.75 + max((lightmap.x - 0.05) * 0.925, 0.0) * (screenBrightness*0.25 + 0.9);
	#endif
	
	#ifdef BLOCKLIGHT_FLICKER
		newLightmap *= min(((1 - clamp(sin(fract(frametime*2.7) + frametime*3.7) - 0.75, 0.0, 0.25) * BLOCKLIGHT_FLICKER_STRENGTH)
					* max(fract(frametime*0.7), (1 - BLOCKLIGHT_FLICKER_STRENGTH * 0.25))) / (1.0 - BLOCKLIGHT_FLICKER_STRENGTH * 0.2)
					, 0.8) * 1.25
					* 0.8 + 0.2 * clamp((cos(fract(frametime*0.47) * fract(frametime*1.17) + fract(frametime*2.17))) * 1.5, 1.0 - BLOCKLIGHT_FLICKER_STRENGTH * 0.25, 1.0);
	#endif

    vec3 blockLighting = blocklightCol * newLightmap * newLightmap;

	#if !defined TEN || !defined DARK_TEN
   		float minLighting = 0.000000000001 + (MIN_LIGHT * 0.0035 * (screenBrightness*0.08 + 0.01)) * (1.0 - eBS);
	#else
   		float minLighting = 0.0;
	#endif
	
    vec3 emissiveLighting = albedo.rgb * (emissive * 4.0 / pow(quarterNdotU, SHADING_STRENGTH)) * EMISSIVE_BRIGHTNESS;

    float nightVisionLighting = nightVision * 0.25;

	#ifndef COMPATIBILITY_MODE
		if (!(mat < 1.75 && mat > 0.75)) {
			smoothLighting = pow(smoothLighting, 
								2.0 - min(length(fullShadow) + lightmap.x, 1.0)
								);
		} else {
			smoothLighting = smoothLighting * smoothLighting;
		}
	#endif

    albedo *= sceneLighting + blockLighting + emissiveLighting + nightVisionLighting + minLighting;
    albedo *= pow(quarterNdotU, SHADING_STRENGTH) * smoothLighting;

	#if defined GBUFFERS_HAND && defined HAND_BLOOM_REDUCTION
		float albedoStrength = (albedo.r + albedo.g + albedo.b) / 10.0;
		if (albedoStrength > 1.0) albedo.rgb = albedo.rgb * max(2.0 - pow(albedoStrength, 1.0), 0.34);
	#endif
}