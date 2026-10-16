Code
[[

	static const float GLOBE_PI        = 3.14159265f;
	static const float GLOBE_CAM_FLAT  = 900.0f;
	static const float GLOBE_CAM_CURVE = 1000.0f;
	static const float GLOBE_CAM_FULL  = 1800.0f;
	static const float GLOBE_EQUATOR   = 1280.0f / 2560.0f;
	static const float GLOBE_MIN_BLEND = 0.02f;

	float GlobeRadiusFull() { return MAP_SIZE_X / ( 2.0f * GLOBE_PI ); }

	float GlobeBlend() { return smoothstep( GLOBE_CAM_CURVE, GLOBE_CAM_FULL, vCamPos.y ); }

	float GlobeOceanWeight() { return smoothstep( GLOBE_CAM_FLAT, GLOBE_CAM_CURVE, vCamPos.y ); }

	float GlobeWaterWeight() { return GlobeOceanWeight(); }

	float GlobeRadius() { return GlobeRadiusFull() / max( GlobeBlend(), GLOBE_MIN_BLEND ); }

	float2 GlobeFocus()
	{
		float3 vDir = normalize( vCamLookAtDir );
		float vT = max( 0.0f, vCamPos.y - WATER_HEIGHT ) / max( 0.05f, -vDir.y );
		float2 vFocus = vCamPos.xz + vDir.xz * vT;
		vFocus.y = clamp( vFocus.y, 0.0f, MAP_SIZE_Y );
		return vFocus;
	}

	float GlobeLatitude( float vRow )
	{
		float vProjected = ( clamp( vRow, 0.0f, MAP_SIZE_Y ) - GLOBE_EQUATOR * MAP_SIZE_Y ) / GlobeRadiusFull();
		return 2.5f * atan( exp( 0.8f * vProjected ) ) - 0.625f * GLOBE_PI;
	}

	float GlobeGeo() { return smoothstep( 0.5f, 1.0f, GlobeBlend() ); }

	float GlobeFocusLatitude() { return GlobeLatitude( GlobeFocus().y ) * GlobeGeo(); }

	float3 GlobeNormal( float3 vFlatPos )
	{
		float vBlend = GlobeBlend();
		float vScale = max( vBlend, GLOBE_MIN_BLEND );
		float vGeo = GlobeGeo();
		float2 vFocus = GlobeFocus();
		float vN = GlobeRadiusFull();
		float vLon = ( vFlatPos.x - vFocus.x ) / vN;
		vLon -= floor( vLon / ( 2.0f * GLOBE_PI ) + 0.5f ) * 2.0f * GLOBE_PI;
		vLon *= vScale;
		float vLatFocus = GlobeFocusLatitude();
		float vDLat = lerp( ( vFlatPos.z - vFocus.y ) / vN, GlobeLatitude( vFlatPos.z ) - GlobeLatitude( vFocus.y ), vGeo ) * vScale;
		float vLat = vLatFocus + vDLat;
		float3 vP = float3( cos( vLat ) * sin( vLon ), sin( vLat ), cos( vLat ) * cos( vLon ) );
		float3 vUp = float3( 0.0f, sin( vLatFocus ), cos( vLatFocus ) );
		float3 vNorth = float3( 0.0f, cos( vLatFocus ), -sin( vLatFocus ) );
		return normalize( float3( vP.x, dot( vP, vUp ), dot( vP, vNorth ) ) );
	}

	float3 GlobePosition( float3 vFlatPos )
	{
		float vBlend = GlobeBlend();
		if ( vBlend <= 0.0f )
			return vFlatPos;
		float2 vFocus = GlobeFocus();
		float3 vNormal = GlobeNormal( vFlatPos );
		float3 vOffset = ( vNormal - float3( 0.0f, 1.0f, 0.0f ) ) * GlobeRadius() + vNormal * ( vFlatPos.y - WATER_HEIGHT );
		float3 vCurvedPos = float3( vFocus.x, WATER_HEIGHT, vFocus.y ) + vOffset;

		return lerp( vFlatPos, vCurvedPos, saturate( vBlend / GLOBE_MIN_BLEND ) );
	}

	float3 GlobeWarp( float3 vFlatPos ) { return GlobePosition( vFlatPos ); }

	float3 GlobeCenter()
	{
		float2 vFocus = GlobeFocus();
		return float3( vFocus.x, WATER_HEIGHT - GlobeRadius(), vFocus.y );
	}

	float GlobeFacing( float3 vFlatPos )
	{
		if ( GlobeBlend() <= 0.0f )
			return 1.0f;
		return dot( GlobeNormal( vFlatPos ), normalize( vCamPos - GlobePosition( vFlatPos ) ) );
	}

	float GlobeVisible( float3 vFlatPos )
	{
		if ( GlobeBlend() <= 0.0f )
			return 1.0f;
		float vRows = min( vFlatPos.z + 2.0f, MAP_SIZE_Y + 2.0f - vFlatPos.z );
		return min( vRows, GlobeFacing( vFlatPos ) );
	}

	float3 GlobeOcean( float3 vFlatPos, float vShallow )
	{
		float3 vNormal = GlobeNormal( vFlatPos );
		float3 vToEye = normalize( vCamPos - GlobePosition( vFlatPos ) );
		float3 vSun = normalize( vToEye + float3( -0.5f, 0.45f, -0.18f ) );
		float3 vColor = lerp( float3( 0.004f, 0.030f, 0.070f ), float3( 0.015f, 0.100f, 0.145f ), saturate( vShallow ) );
		float vLight = 0.6f + 0.4f * saturate( dot( vNormal, vSun ) );
		float vRim = pow( 1.0f - saturate( dot( vNormal, vToEye ) ), 4.0f );
		return vColor * vLight * ( 1.0f - 0.2f * vRim ) + float3( 0.017f, 0.07f, 0.19f ) * vRim * 0.6f;
	}

	float3 GlobeSky( float3 vSkyColor, float3 vWorldPos )
	{
		float vWeight = smoothstep( 0.2f, 0.35f, GlobeBlend() );
		if ( vWeight <= 0.0f )
			return vSkyColor;
		float3 vRay = normalize( vWorldPos - vCamPos );
		float3 vOffset = vCamPos - GlobeCenter();
		float vR = GlobeRadius();
		float vAlong = dot( vOffset, vRay );
		float vMiss = length( vOffset - vRay * min( vAlong, 0.0f ) );
		float3 vColor = float3( 0.0015f, 0.003f, 0.008f );
		float vHalo = pow( saturate( 1.0f - ( vMiss - vR ) / ( vR * 0.05f ) ), 3.0f ) * step( vR, vMiss );
		vColor += float3( 0.02f, 0.10f, 0.28f ) * vHalo * 0.6f;
		float vDisc = vAlong * vAlong - dot( vOffset, vOffset ) + vR * vR;
		if ( vDisc >= 0.0f && vAlong < 0.0f )
		{

			float3 vRadial = normalize( vOffset + vRay * ( -vAlong - sqrt( vDisc ) ) );
			float3 vSun = normalize( -vRay + float3( -0.5f, 0.45f, -0.18f ) );
			float vLatF = GlobeFocusLatitude();
			float vSinLat = vRadial.y * sin( vLatF ) + vRadial.z * cos( vLatF );
			float vIce = smoothstep( 0.955f, 0.985f, abs( vSinLat ) );
			float3 vSurface = lerp( float3( 0.004f, 0.030f, 0.070f ), float3( 0.30f, 0.34f, 0.40f ), vIce );
			vColor = vSurface * ( 0.6f + 0.4f * saturate( dot( vRadial, vSun ) ) );
		}
		return lerp( vSkyColor, vColor, vWeight );
	}
]]
