/* 
BSL Shaders v7.1.05 by Capt Tatsu, Complementary Shaders by EminGT
*/ 

//Settings//
#include "/lib/settings.glsl"

//Fragment Shader///////////////////////////////////////////////////////////////////////////////////
#ifdef FSH

//Extensions//

//Varyings//
varying float mat;
varying float dist;

varying vec2 texCoord, lmCoord;

varying vec3 normal, binormal, tangent;
varying vec3 sunVec, upVec;
varying vec3 viewVector;

varying vec4 color;

#ifdef ADVANCED_MATERIALS
varying vec4 vTexCoord, vTexCoordAM;
#endif

//Uniforms//
uniform int frameCounter;
uniform int isEyeInWater;
uniform int worldTime;
uniform int worldDay;

uniform float frameTimeCounter;
uniform float blindFactor, nightVision;
uniform float far, near;
uniform float rainStrength;
uniform float screenBrightness; 
uniform float shadowFade;
uniform float timeAngle, timeBrightness;
uniform float viewWidth, viewHeight;
uniform float eyeAltitude;
uniform float sunAngle;

uniform ivec2 eyeBrightnessSmooth;

uniform vec3 cameraPosition, previousCameraPosition;
uniform vec3 skyColor;
uniform vec3 fogColor;

uniform mat4 gbufferProjection, gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferModelView, gbufferPreviousModelView, gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

uniform sampler2D texture;
uniform sampler2D gaux2;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;

#ifdef ADVANCED_MATERIALS
uniform sampler2D specular;
uniform sampler2D normals;

#if defined REFLECTION_ROUGH && defined ADVANCED_MATERIALS && WATER_TYPE == 2
uniform sampler2D depthtex0;
#endif
#endif

//Optifine Constants//
#ifdef ADVANCED_MATERIALS
const bool gaux2MipmapEnabled = true;
#endif

//Common Variables//
float eBS = eyeBrightnessSmooth.y / 240.0;
float sunVisibility  = clamp(dot( sunVec,upVec) + 0.05, 0.0, 0.1) * 10.0;
float moonVisibility = clamp(dot(-sunVec,upVec) + 0.05, 0.0, 0.1) * 10.0;

#if WORLD_TIME_ANIMATION == 2
float modifiedWorldDay = worldDay - int(worldDay*0.01) * 100 + 10.1;
float frametime = (worldTime + modifiedWorldDay * 24000) * 0.05 * ANIMATION_SPEED;
float cloudtime = frametime;
#endif
#if WORLD_TIME_ANIMATION == 1
float modifiedWorldDay = worldDay - int(worldDay*0.01) * 100 + 10.1;
float frametime = frameTimeCounter * ANIMATION_SPEED;
float cloudtime = (worldTime + modifiedWorldDay * 24000) * 0.05 * ANIMATION_SPEED;
#endif
#if WORLD_TIME_ANIMATION == 0
float frametime = frameTimeCounter * ANIMATION_SPEED;
float cloudtime = frametime;
#endif

#ifdef ADVANCED_MATERIALS
vec2 dcdx = dFdx(texCoord.xy);
vec2 dcdy = dFdy(texCoord.xy);
#endif

vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);

//Common Functions//
float GetLuminance(vec3 color){
	return dot(color,vec3(0.299, 0.587, 0.114));
}

float InterleavedGradientNoise(){
	float n = 52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y);
	return fract(n + frameCounter / 8.0);
}

float GetWaterHeightMap(vec3 worldPos, vec3 nViewPos){
    float noise = 0.0;

    float mult = clamp(-dot(normalize(normal), nViewPos) * 8.0, 0.0, 1.0) / 
                 sqrt(sqrt(max(dist, 4.0)));
    
    vec2 wind = vec2(frametime) * 0.425;
    float verticalOffset = worldPos.y * 0.2;

    if (mult > 0.01){
        float lacunarity = 1.0 / WATER_SIZE, persistance = 1.0, weight = 0.0;

        mult *= WATER_BUMP * (lmCoord.y*0.9 + 0.1) * WATER_SIZE / 450.0;
        wind *= WATER_SPEED;

        for(int i = 0; i < WATER_OCTAVE; i++){
            float windSign = mod(i,2) * 2.0 - 1.0;
			vec2 noiseCoord = worldPos.xz + wind * windSign - verticalOffset;
            if (i < 7) noise += texture2D(noisetex, noiseCoord * lacunarity).r * persistance;
			else {
				noise += texture2D(noisetex, noiseCoord * lacunarity * 0.125).r * persistance * 10.0;
				noise = -noise;
				float noisePlus = 1.0 + 0.125 * -noise;
				noisePlus *= noisePlus;
				noisePlus *= noisePlus;
				noise *= noisePlus;
			}

            if (i == 0) noise = -noise;

            weight += persistance;
            lacunarity *= WATER_LACUNARITY;
            persistance *= WATER_PERSISTANCE;
        }
        noise *= mult / weight;
    }

    return noise;
}

vec3 GetParallaxWaves(vec3 worldPos, vec3 nViewPos, float lViewPos, vec3 viewVector) {
	vec3 parallaxPos = worldPos;
	
	for(int i = 0; i < 4; i++){
		float height = (GetWaterHeightMap(parallaxPos, nViewPos) - 0.5) * min(0.2 + lViewPos * 0.025, 1.0);
		parallaxPos.xz += height * viewVector.xy / dist;
	}
	return parallaxPos;
}

vec3 GetWaterNormal(vec3 worldPos, vec3 nViewPos, float lViewPos, vec3 viewVector){
	#if WATER_TYPE == 0 || defined WATER_FORCED
		vec3 waterPos = worldPos + cameraPosition;
		#ifdef WATER_PARALLAX
			waterPos = GetParallaxWaves(waterPos, nViewPos, lViewPos, viewVector);
		#endif

		float normalOffset = WATER_SHARPNESS;

		//float h0 = GetWaterHeightMap(waterPos, nViewPos);
		float h1 = GetWaterHeightMap(waterPos + vec3( normalOffset, 0.0, 0.0), nViewPos);
		float h2 = GetWaterHeightMap(waterPos + vec3(-normalOffset, 0.0, 0.0), nViewPos);
		float h3 = GetWaterHeightMap(waterPos + vec3(0.0, 0.0,  normalOffset), nViewPos);
		float h4 = GetWaterHeightMap(waterPos + vec3(0.0, 0.0, -normalOffset), nViewPos);

		float xDelta = (h1 - h2) / normalOffset;
		float yDelta = (h3 - h4) / normalOffset;

		vec3 normalMap = vec3(xDelta, yDelta, 1.0 - (xDelta * xDelta + yDelta * yDelta));
		vec3 roughMap = normalMap;

		#if defined REFLECTION_ROUGH && defined ADVANCED_MATERIALS && WATER_TYPE == 2
			vec2 newCoord = vTexCoord.st * vTexCoordAM.pq + vTexCoordAM.st;
			roughMap = texture2DGradARB(depthtex0, newCoord*2097152, dcdx, dcdy).xyz;
			normalMap = normalMap + roughMap - vec3(0.5, 0.5, 1.0);
		#endif

		return normalMap * 0.03 + vec3(0.0, 0.0, 0.75);
	#else
		#if defined REFLECTION_ROUGH && defined ADVANCED_MATERIALS && WATER_TYPE == 2
			vec2 newCoord = vTexCoord.st * vTexCoordAM.pq + vTexCoordAM.st;
			vec3 roughMap = texture2DGradARB(depthtex0, newCoord*2097152, dcdx, dcdy).xyz;
			roughMap = roughMap - vec3(0.5, 0.5, 1.0);
		
			return (roughMap + vec3(0.5, 0.5, 1.0)) * 0.03 + vec3(-0.016, -0.016, 0.75);
		#else
			return vec3(0.0, 0.0, 0.97);	
		#endif
	#endif
}

//Includes//
#include "/lib/color/blocklightColor.glsl"
#include "/lib/color/dimensionColor.glsl"
#include "/lib/color/skyColor.glsl"
#include "/lib/color/waterColor.glsl"
#include "/lib/surface/ggx.glsl"
#include "/lib/util/dither.glsl"
#include "/lib/reflections/raytracewater.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/lighting/forwardLighting.glsl"
#include "/lib/reflections/simpleReflections.glsl"

#ifdef WATER_CAUSTICS
#ifdef OVERWORLD
#include "/lib/lighting/caustics.glsl"
#endif
#endif

#ifdef OVERWORLD
#include "/lib/atmospherics/clouds.glsl"
#include "/lib/atmospherics/sky.glsl"
#endif

#include "/lib/atmospherics/fog.glsl"

#if defined END && defined CLOUDS
#include "/lib/color/lightColor.glsl"
#include "/lib/atmospherics/clouds.glsl"
#include "/lib/atmospherics/sky.glsl"
#endif

#if AA == 2 || AA == 3
#include "/lib/util/jitter.glsl"
#endif
#if AA == 4
#include "/lib/util/jitter2.glsl"
#endif

#ifdef ADVANCED_MATERIALS
#include "/lib/surface/directionalLightmap.glsl"
#include "/lib/reflections/complexFresnel.glsl"
#include "/lib/surface/materialGbuffers.glsl"
#include "/lib/surface/parallax.glsl"
#endif

//Program//
void main(){
    vec4 albedo = texture2D(texture, texCoord) * vec4(color.rgb, 1.0);
	
	#ifdef GREY
		albedo.rgb = vec3((albedo.r + albedo.g + albedo.b) / 3);
	#endif
	
	vec3 newNormal = normal;
	vec3 newRough = normal;
	
	#ifdef ADVANCED_MATERIALS
		vec2 newCoord = vTexCoord.st * vTexCoordAM.pq + vTexCoordAM.st;
	
		#if defined PARALLAX || defined SELF_SHADOW
			float parallaxFade = clamp((dist - PARALLAX_DISTANCE) / 32.0, 0.0, 1.0);
			float skipParallax = float(mat > 0.98 && mat < 1.02) + 
								 float(mat > 3.98 && mat < 4.02);
		#endif
	
		#ifdef PARALLAX
			float materialFormatParallax = 0.0;
			GetParallaxCoord(parallaxFade, newCoord, materialFormatParallax);
			if (materialFormatParallax + skipParallax < 0.5) albedo = texture2DGradARB(texture, newCoord, dcdx, dcdy) * vec4(color.rgb, 1.0);
		#endif
	
		float smoothness = 0.0, metalData = 0.0, skymapMod = 0.0;
		vec3 spec = vec3(0.0);
	#endif

	float emissive = 0.0;

	vec3 vlAlbedo = vec3(1.0);
	vec3 worldPos = vec3(0.0);
	
	#ifndef COMPATIBILITY_MODE
		float albedocheck = albedo.a;
	#else
		float albedocheck = albedo.a*100000;
	#endif

	if (albedocheck > 0.00001){
		vec2 lightmap = clamp(lmCoord, vec2(0.0), vec2(1.0));
		
		float water            = float(mat > 0.98 && mat < 1.02);
		float translucent      = float(mat > 1.98 && mat < 2.02);
		float netherportal 	   = float(mat > 2.98 && mat < 3.02);
		float moddedfluid  	   = float(mat > 3.98 && mat < 4.02);
		
		#ifndef REFLECTION_TRANSLUCENT
			translucent = 0.0;
		#endif

		vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
		#if AA > 1
			vec3 viewPos = ToNDC(vec3(TAAJitter(screenPos.xy, -0.5), screenPos.z));
		#else
			vec3 viewPos = ToNDC(screenPos);
		#endif
		worldPos = ToWorld(viewPos);
		vec3 nViewPos = normalize(viewPos.xyz);
		float NdotU = dot(nViewPos, upVec);
		float lViewPos = length(viewPos.xyz);

		vec3 normalMap = vec3(0.0, 0.0, 1.0);
		
		mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
							  tangent.y, binormal.y, normal.y,
							  tangent.z, binormal.z, normal.z);

		if (water > 0.5){
			normalMap = GetWaterNormal(worldPos, nViewPos, lViewPos, viewVector);
			newNormal = clamp(normalize(normalMap * tbnMatrix), vec3(-1.0), vec3(1.0));

			#ifndef COMPATIBILITY_MODE
		    	albedo.a = sqrt(albedo.a);
			#endif
		}

		#ifdef ADVANCED_MATERIALS
			float metalness = 0.0, f0 = 0.0, ao = 1.0; 
			vec3 roughMap = vec3(0.0);
			float materialFormat = 0.0;
			if (water + moddedfluid < 0.5) {
				GetMaterials(materialFormat, smoothness, metalness, f0, metalData, emissive, ao, normalMap, roughMap,
							newCoord, dcdx, dcdy);
				if (normalMap.x > -0.999 && normalMap.y > -0.999)
					newNormal = clamp(normalize(normalMap * tbnMatrix), vec3(-1.0), vec3(1.0));
			}
			if (materialFormat > 0.5) {
				#if !defined COMPATIBILITY_MODE && defined EMISSIVE_NETHER_PORTAL
					if (netherportal > 0.5) emissive = 0.25, albedo.r *= 1.5, albedo.a *= max(pow(albedo.r, 8.0), 0.025), lightmap = vec2(0.0);
				#endif
			}
		#endif
		
		if (moddedfluid > 0.5) albedo = texture2D(texture, texCoord) * vec4(color.rgb, 1.0);

    	if (water < 0.5) albedo.rgb = pow(albedo.rgb, vec3(2.2));

		float fresnel = pow(clamp(1.0 + dot(newNormal, nViewPos), 0.0, 1.0), 5.0);

		#if WATER_TYPE == 1
			if (water > 0.5) albedo.rgb = pow(albedo.rgb, vec3(2.5));
		#endif
		
		#if WATER_TYPE == 2
			if (water > 0.5) {
				albedo.rgb = vec3(0.4, 0.5, 0.4) * (pow(albedo.rgb, vec3(5.0)) + 4 * waterColor.rgb * pow(albedo.r, 4.0)
											+ 16 * waterColor.rgb * pow(albedo.g, 4.0) + 4 * waterColor.rgb * pow(albedo.b, 4.0));
				albedo.rgb = min(albedo.rgb * (1 + length(albedo.rgb) * pow(WATER_A, 32.0) * 50.0), vec3(2.0));

				//if (isEyeInWater == 1) albedo.a = 1.0;
			}
		#endif

		#ifdef WHITE_WORLD
			albedo.rgb = vec3(0.5);
		#endif
		
		#if WATER_TYPE == 0
			if (water > 0.5) {
				vec3 customWaterColor = vec3(waterColor.rgb * waterColor.rgb * 10 * waterColor.a);

				#if MC_VERSION >= 11300
					vec3 vanillaWaterColor = pow(color.rgb, vec3(2.2)) * waterColor.a;
					float modifiedWaterAlpha = waterAlpha;
					if (isEyeInWater == 1) modifiedWaterAlpha *= sqrt(fresnel);
				#else
					vec3 vanillaWaterColor = customWaterColor;
					float modifiedWaterAlpha = 0.5;
				#endif

				vec3 combinedWaterColor = customWaterColor * (1 - WATER_V) + vanillaWaterColor * WATER_V;			
				albedo = vec4(combinedWaterColor*(1 - (max(lightmap.y - 0.80, 0.0))*2), modifiedWaterAlpha);
			}
		#endif

		vlAlbedo = mix(vec3(1.0), albedo.rgb, sqrt(albedo.a)) * (1.0 - pow(albedo.a, 64.0));

		float NdotL = clamp(dot(newNormal, lightVec) * 1.01 - 0.01, 0.0, 1.0);

		float quarterNdotU = clamp(0.25 * dot(newNormal, upVec) + 0.75, 0.5, 1.0);
			  quarterNdotU*= quarterNdotU;

		float parallaxShadow = 1.0;
		#ifdef ADVANCED_MATERIALS
			vec3 rawAlbedo = albedo.rgb * 0.999 + 0.001;
			albedo.rgb *= ao;

			#ifdef REFLECTION_SPECULAR
				float roughnessSqr = (1.0 - smoothness) * (1.0 - smoothness);
				albedo.rgb *= (1.0 - metalness * (1.0 - roughnessSqr));
			#endif
			
			#ifdef SELF_SHADOW
				if (materialFormat < 0.5) {
					if (lightmap.y > 0.0 && NdotL > 0.0 && water < 0.5){
						parallaxShadow = GetParallaxShadow(parallaxFade, newCoord, lightVec, tbnMatrix);
						NdotL *= parallaxShadow;
					}
				}
			#endif

			#ifdef DIRECTIONAL_LIGHTMAP
				if (materialFormat < 0.5) {
					mat3 lightmapTBN = GetLightmapTBN(viewPos);
					lightmap.x = DirectionalLightmap(lightmap.x, lmCoord.x, newNormal, lightmapTBN);
					lightmap.y = DirectionalLightmap(lightmap.y, lmCoord.y, newNormal, lightmapTBN);
				}
			#endif
		#endif
		
		vec3 shadow = vec3(0.0);
		GetLighting(albedo.rgb, shadow, viewPos, worldPos, lightmap, color.a, NdotL, quarterNdotU,
				    parallaxShadow, emissive, 0.0, mat, 0.0);
		
		float dither = Bayer64(gl_FragCoord.xy);

		#ifdef OVERWORLD
			vec3 lightME = mix(lightMorning, lightEvening, mefade);
			vec3 lightDayTint = lightDay * lightME * LIGHT_DI;
			vec3 lightDaySpec = mix(lightME, sqrt(lightDayTint), timeBrightness);
			vec3 specularColor = mix(sqrt(lightNight),
										lightDaySpec,
										sunVisibility);
			specularColor *= specularColor;
		#endif
		#if defined END
			vec3 specularColor = endCol;
		#endif
		#if defined SEVEN || defined SEVEN_2
			vec3 specularColor = vec3(0.005, 0.006, 0.018);
		#endif
		#if defined TEN
			vec3 specularColor = vec3(0.0, 0.0, 0.0);
		#endif

		if (water > 0.5 || moddedfluid > 0.5 || (translucent > 0.5 && albedo.a < 0.95)){
			vec4 reflection = vec4(0.0);
			vec3 skyReflection = vec3(0.0);
	
			fresnel = fresnel * 0.9 + 0.1;
			fresnel*= max(1.0 - isEyeInWater * 0.5 * water, 0.5);
			fresnel*= 1.0 - translucent * (1.0 - albedo.a);
			
			#ifdef REFLECTION
				reflection = SimpleReflection(viewPos, newNormal, dither);
				reflection.rgb = pow(reflection.rgb * 2.0, vec3(8.0));
			#endif
			
			if (reflection.a < 1.0){
				vec3 skyReflectionPos = reflect(nViewPos, newNormal);
				float refNdotU = dot(skyReflectionPos, upVec);

				#ifdef OVERWORLD
					vec3 gotTheSkyColor = vec3(0.0);
					if (isEyeInWater == 0) gotTheSkyColor = GetSkyColor(lightCol, refNdotU, skyReflectionPos, true);
					if (isEyeInWater == 1) gotTheSkyColor = 0.6 * pow(rawWaterColor.rgb * (1.0 - blindFactor), vec3(2.0));
					skyReflection = gotTheSkyColor;

					float specular = 0.0;
					float waterBump = WATER_BUMP;
					if (water + moddedfluid > 0.5) {
						if (waterBump >= 0.25) specular = waterGGX(newNormal, normal, nViewPos, lightVec, 1.0, 0.0, 0.01 * sunVisibility + 0.06);
					} else {
						specular = GGX(newNormal, nViewPos, lightVec, 1.0, 0.0, 0.01 * sunVisibility + 0.06);
					}
					specular *= (1.0 - sqrt(rainStrength)) * shadowFade * (1 - moddedfluid);

					#if WRONG_SKY_REF_FIX == 1
						float skyRefFactor = lightmap.y * lightmap.y * 1.5;
					#elif WRONG_SKY_REF_FIX == 2
						float skyRefFactor = max(lightmap.y - 0.80, 0.0) * 7.5;
					#else
						float skyRefFactor = max(lightmap.y - 0.99, 0.0) * 150.0;
					#endif
					skyReflection *= skyRefFactor;
					skyReflection = min(skyReflection, gotTheSkyColor*1.3);
					float cloudFactor = 1.0;
					#ifdef CLOUDS
						if (isEyeInWater == 0) {
							float cosT = dot(normalize(skyReflectionPos * 100.0), upVec);
							vec4 cloud = DrawCloud(skyReflectionPos * 100.0, dither, lightCol, ambientCol, cosT);
							skyReflection = mix(skyReflection, cloud.rgb*skyRefFactor, cloud.a);
						}
					#endif
					skyReflection += (specular / fresnel) * specularColor * shadow * lightmap.y * lightmap.y * lightmap.y;
				#endif

				#ifdef NETHER
					skyReflection = netherCol * 0.005;
				#endif

				#if defined END || defined SEVEN || defined SEVEN_2
					#if defined END
						skyReflection = endCol * 0.05;
						#if defined CLOUDS
							vec4 cloud = DrawEndCloud(skyReflectionPos * 100.0, dither, endCol);
							skyReflection = mix(skyReflection, cloud.rgb*shadow, cloud.a);
						#endif
					#endif
					#if defined SEVEN || defined SEVEN_2
						skyReflection = vec3(0.005, 0.006, 0.018) * lmCoord.y;
					#endif
					
					float specular = GGX(newNormal, nViewPos, lightVec, 0.4, 0.02, 0.025 * sunVisibility + 0.05);

					skyReflection += (specular / fresnel) * specularColor * shadow;
				#endif

				#ifdef TWENTY
					vec3 twilightGreen = vec3(0.015, 0.03, 0.02);
					vec3 twilightPurple = twilightGreen * 0.1;
					skyReflection = 2 * (twilightPurple * 2 * clamp(pow(refNdotU, 0.7), 0.0, 1.0) + twilightGreen * (1-clamp(pow(refNdotU, 0.7), 0.0, 1.0)));
					if (isEyeInWater > 0.5) skyReflection = pow(rawWaterColor.rgb * (1.0 - blindFactor), vec3(2.0)) * fresnel;
				#endif
			}
			
			reflection.rgb =  max(mix(skyReflection, reflection.rgb, reflection.a), vec3(0.0));
			
			albedo.rgb = 0.75 * mix(albedo.rgb, reflection.rgb, fresnel);
			albedo.a = mix(albedo.a, 1.0, fresnel);
		}else{
			#ifdef ADVANCED_MATERIALS
				skymapMod = lightmap.y * lightmap.y * (3.0 - 2.0 * lightmap.y);

				#ifdef REFLECTION_SPECULAR
					#if MATERIAL_FORMAT == 0
						vec3 fresnel3 = mix(mix(vec3(f0), rawAlbedo * 0.8, metalness), vec3(1.0), fresnel);
						if (f0 >= 0.9 && f0 < 1.0) fresnel3 = ComplexFresnel(fresnel, f0);
					#else
						vec3 fresnel3 = mix(mix(vec3(0.02), rawAlbedo * 0.8, metalness), vec3(1.0), fresnel);
					#endif
					fresnel3 *= smoothness;

					if (length(fresnel3) > 0.005){
						vec4 reflection = vec4(0.0);
						vec3 skyReflection = vec3(0.0);
						
						reflection = SimpleReflection(viewPos, newNormal, dither);
						reflection.rgb = pow(reflection.rgb * 2.0, vec3(8.0));

						if (reflection.a < 1.0){
							#ifdef OVERWORLD
								vec3 skyReflectionPos = reflect(nViewPos, newNormal);
								float refNdotU = dot(skyReflectionPos, upVec);
								skyReflection = GetSkyColor(lightCol, refNdotU, skyReflectionPos, true);
								skyReflection = mix(vec3(0.001), skyReflection * (4.0 - 3.0 * eBS), skymapMod);
							#endif
							#if defined END
								skyReflection = endCol * 0.01;
							#endif
							#if defined SEVEN || defined SEVEN_2
								skyReflection = vec3(0.005, 0.006, 0.018);
							#endif
						}

						reflection.rgb = max(mix(skyReflection, reflection.rgb, reflection.a), vec3(0.0));

						albedo.rgb = albedo.rgb * (1.0 - fresnel3 * (1.0 - metalness)) +
									reflection.rgb * fresnel3;
						albedo.a = mix(albedo.a, 1.0, GetLuminance(fresnel3));
					}
				#endif

				#if defined OVERWORLD || defined END || defined SEVEN || defined SEVEN_2
					albedo.rgb += lightmap.y * GetSpecularHighlight(smoothness, metalness, f0, specularColor, rawAlbedo,
													shadow, newNormal, viewPos, materialFormat);
				#endif
			#endif
		}
		
		#if defined WATER_CAUSTICS && defined OVERWORLD
			if (isEyeInWater == 1){
			float skyLightMap = lightmap.y * lightmap.y * (3.0 - 2.0 * lightmap.y);
			albedo.rgb = GetCaustics(albedo.rgb, worldPos.xyz, cameraPosition.xyz, shadow, skyLightMap, lightmap.x);
			}
		#endif

		albedo.rgb = startFog(albedo.rgb, nViewPos, lViewPos, worldPos, NdotU);

		#ifdef SHOW_LIGHT_LEVELS
			float showLightLevelFactor = fract(frameTimeCounter);
			if (showLightLevelFactor > 0.5) showLightLevelFactor = 1 - showLightLevelFactor;
			if (lmCoord.x < 0.5 && quarterNdotU > 0.99 && (mat < 0.95 || mat > 1.05)) albedo.rgb += vec3(0.5, 0.0, 0.0) * showLightLevelFactor;
		#endif
	} else albedo.a = 0.0;

    /* DRAWBUFFERS:01 */
    gl_FragData[0] = albedo;
	gl_FragData[1] = vec4(vlAlbedo, 1.0);
}

#endif

//Vertex Shader/////////////////////////////////////////////////////////////////////////////////////
#ifdef VSH

//Varyings//
varying float mat;
varying float dist;

varying vec2 texCoord, lmCoord;

varying vec3 normal, binormal, tangent;
varying vec3 sunVec, upVec;
varying vec3 viewVector;

varying vec4 color;

#ifdef ADVANCED_MATERIALS
varying vec4 vTexCoord, vTexCoordAM;
#endif

//Uniforms//
uniform int worldTime;

uniform float frameTimeCounter;
uniform float timeAngle;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView, gbufferModelViewInverse;

#if AA > 1
uniform int frameCounter;

uniform float viewWidth, viewHeight;
#endif

//Attributes//
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec4 at_tangent;

//Common Variables//
#if WORLD_TIME_ANIMATION >= 2
float frametime = float(worldTime) * 0.05 * ANIMATION_SPEED;
#else
float frametime = frameTimeCounter * ANIMATION_SPEED;
#endif

//Common Functions//
float WavingWater(vec3 worldPos, bool displacement){
	float fractY = fract(worldPos.y + cameraPosition.y + 0.005);
		
	if (displacement == true) {
		float wave = sin(6.28 * (frametime * 0.7 + worldPos.x * 0.14 + worldPos.z * 0.07)) +
					sin(6.28 * (frametime * 0.5 + worldPos.x * 0.10 + worldPos.z * 0.20));
		if (fractY > 0.01) return wave * 0.0125;
	}
	
	return 0.0;
}

//Includes//
#if AA == 2 || AA == 3
#include "/lib/util/jitter.glsl"
#endif
#if AA == 4
#include "/lib/util/jitter2.glsl"
#endif

#ifdef WORLD_CURVATURE
#include "/lib/vertex/worldCurvature.glsl"
#endif

//Program//
void main(){
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    
	lmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	lmCoord = clamp((lmCoord - 0.03125) * 1.06667, 0.0, 1.0);
	lmCoord.x = pow(lmCoord.x, 0.5)*0.87;

	normal   = normalize(gl_NormalMatrix * gl_Normal);
	binormal = normalize(gl_NormalMatrix * cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w);
	tangent  = normalize(gl_NormalMatrix * at_tangent.xyz);
	
	mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
						  tangent.y, binormal.y, normal.y,
						  tangent.z, binormal.z, normal.z);
								  
	viewVector = tbnMatrix * (gl_ModelViewMatrix * gl_Vertex).xyz;
	
	dist = length(gl_ModelViewMatrix * gl_Vertex);

	#ifdef ADVANCED_MATERIALS
		vec2 midCoord = (gl_TextureMatrix[0] *  mc_midTexCoord).st;
		vec2 texMinMidCoord = texCoord - midCoord;

		vTexCoordAM.pq  = abs(texMinMidCoord) * 2;
		vTexCoordAM.st  = min(texCoord, midCoord - texMinMidCoord);
		
		vTexCoord.xy    = sign(texMinMidCoord) * 0.5 + 0.5;
	#endif
    
	color = gl_Color;
	
	mat = 0.0;
	
	if (mc_Entity.x == 79 || mc_Entity.x == 7979) mat = 2.0;
	if (mc_Entity.x == 8) lmCoord.x *= 0.75;
	#if !defined COMPATIBILITY_MODE && defined EMISSIVE_NETHER_PORTAL
		if (mc_Entity.x == 80) mat = 3.0;
	#endif

	const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
	float ang = fract(timeAngle - 0.25);
	ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
	sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

	upVec = normalize(gbufferModelView[1].xyz);

	vec4 position = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;
	
	float istopv = gl_MultiTexCoord0.t < mc_midTexCoord.t ? 1.0 : 0.0;
	if (mc_Entity.x == 8){
		#ifndef WATER_DISPLACEMENT
			position.y += WavingWater(position.xyz, false);
		#else
			position.y += WavingWater(position.xyz, true);
		#endif
		mat = 1.0;
	}
	if (mc_Entity.x == 888){
		position.y += WavingWater(position.xyz, false);
		mat = 4.0;
	}

    #ifdef WORLD_CURVATURE
		position.y -= WorldCurvature(position.xz);
    #endif

	gl_Position = gl_ProjectionMatrix * gbufferModelView * position;
	if (mat == 0.0) gl_Position.z -= 0.00001;
	
	#if AA > 1
		gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}

#endif