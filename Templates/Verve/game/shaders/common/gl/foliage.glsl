//-----------------------------------------------------------------------------
// Torque
// Copyright GarageGames, LLC 2011
//-----------------------------------------------------------------------------

// CornerId corresponds to this arrangement
// from the perspective of the camera.
//
//    3 ---- 2
//    |      |
//    0 ---- 1
//

#define MAX_COVERTYPES 8

uniform vec3 gc_camRight;
uniform vec3 gc_camUp;
uniform vec4 gc_typeRects[MAX_COVERTYPES];
uniform vec2 gc_fadeParams;               
uniform vec2 gc_windDir;               

// .x = gust length
// .y = premultiplied simulation time and gust frequency
// .z = gust strength
uniform vec3 gc_gustInfo;

// .x = premultiplied simulation time and turbulance frequency
// .y = turbulance strength
uniform vec2 gc_turbInfo;


//static float sMovableCorner[4] = { 0.0, 0.0, 1.0, 1.0 };


///////////////////////////////////////////////////////////////////////////////
// The following wind effect was derived from the GPU Gems 3 chapter...
//
// "Vegetation Procedural Animation and Shading in Crysis"
// by Tiago Sousa, Crytek
//

vec2 smoothCurve( vec2 x )
{
   return x * x * ( 3.0 - 2.0 * x );
}

vec2 triangleWave( vec2 x )
{
   return abs( fract( x + 0.5 ) * 2.0 - 1.0 );
}

vec2 smoothTriangleWave( vec2 x )
{
   return smoothCurve( triangleWave( x ) );
}

float windTurbulence( float bbPhase, float frequency, float strength )
{
   // We create the input value for wave generation from the frequency and phase.
   vec2 waveIn = vec2( bbPhase + frequency );

   // We use two square waves to generate the effect which
   // is then scaled by the overall strength.
   vec2 waves = ( fract( waveIn.xy * vec2( 1.975, 0.793 ) ) * 2.0 - 1.0 );
   waves = smoothTriangleWave( waves );

   // Sum up the two waves into a single wave.
   return ( waves.x + waves.y ) * strength;
}

vec2 windEffect(   float bbPhase, 
                     vec2 windDirection,
                     float gustLength,
                     float gustFrequency,
                     float gustStrength,
                     float turbFrequency,
                     float turbStrength )
{
   // Calculate the ambient wind turbulence.
   float turbulence = windTurbulence( bbPhase, turbFrequency, turbStrength );

   // We simulate the overall gust via a sine wave.
   float gustPhase = clamp( sin( ( bbPhase - gustFrequency ) / gustLength ) , 0.0, 1.0 );
   float gustOffset = ( gustPhase * gustStrength ) + ( ( 0.2 + gustPhase ) * turbulence );

   // Return the final directional wind effect.
   return vec2(gustOffset) * windDirection.xy;
}
   
void foliageProcessVert( inout vec3 position, 
                         inout vec4 diffuse, 
                         in vec4 texCoord, 
                         out vec2 outTexCoord, 
                         inout vec3 normal, 
                         inout vec3 T,
                         in vec3 eyePos )
{  

   float sCornerRight[4];
   sCornerRight[0] = -0.5;
   sCornerRight[1] = 0.5;
   sCornerRight[2] = 0.5;
   sCornerRight[3] = -0.5;

   float sCornerUp[4];
   sCornerUp[0] = 0.0;
   sCornerUp[1] = 0.0;
   sCornerUp[2] = 1.0;
   sCornerUp[3] = 1.0;

   vec2 sUVCornerExtent[4];
   sUVCornerExtent[0] = vec2( 0.0, 1.0 );
   sUVCornerExtent[1] = vec2( 1.0, 1.0 ); 
   sUVCornerExtent[2] = vec2( 1.0, 0.0 ); 
   sUVCornerExtent[3] = vec2( 0.0, 0.0 );


   // Assign the normal and tagent values.
   //normal = cross( gc_camUp, gc_camRight );
   T = gc_camRight;
   
   // Pull out local vars we need for work.
   int corner = int( ( diffuse.a * 255.0 ) + 0.5 );
   vec2 size = texCoord.xy;
   int type = int( texCoord.z );
           
   // The billboarding is based on the camera direction.
   vec3 rightVec   = gc_camRight * sCornerRight[corner];
   vec3 upVec      = gc_camUp * sCornerUp[corner];               
   
   // Figure out the corner position.     
   vec3 outPos = ( upVec * size.y ) + ( rightVec * size.x );
   float len = length( outPos.xyz );
   
   // We derive the billboard phase used for wind calculations from its position.
   float bbPhase = dot( position.xyz, vec3( 1.0 ) );

   // Get the overall wind gust and turbulence effects.
   vec3 wind;
   wind.xy = windEffect(   bbPhase,
                           gc_windDir,
                           gc_gustInfo.x, gc_gustInfo.y, gc_gustInfo.z,
                           gc_turbInfo.x, gc_turbInfo.y );
   wind.z = 0.0;

   // Add the summed wind effect into the point.
   outPos.xyz += wind.xyz * texCoord.w;

   // Do a simple spherical clamp to keep the foliage
   // from stretching too much by wind effect.
   outPos.xyz = normalize( outPos.xyz ) * len;

   // Move the point into world space.
   position += outPos;      

   // Grab the uv set and setup the texture coord.
   vec4 uvSet = gc_typeRects[type]; 
   outTexCoord.x = uvSet.x + ( uvSet.z * sUVCornerExtent[corner].x );
   outTexCoord.y = uvSet.y + ( uvSet.w * sUVCornerExtent[corner].y );

   // Animate the normal to get lighting changes
   // across the the wind swept foliage.
   // 
   // TODO: Expose the 10x as a factor to control
   // how much the wind effects the lighting on the grass.
   //
   normal.xy += wind.xy * ( 10.0 * texCoord.w );
   normal = normalize( normal );


   // Get the alpha fade value.
   
   float    fadeStart      = gc_fadeParams.x;
   float    fadeEnd        = gc_fadeParams.y;
   float fadeRange   = fadeEnd - fadeStart;     
   
   float dist = distance( eyePos, position.xyz ) - fadeStart;
   diffuse.a = 1.0 - clamp( dist / fadeRange, 0.0, 1.0 );
}