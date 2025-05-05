#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <clientprefs>

#define PLUGIN_VERSION "2.0"

new Handle:cvarEnable, Handle:cvarDamageAmount, Handle:cvarTeam, Handle:cvarMaxClimbs, Handle:cvarCooldown, Handle:cvarNextClimb;
new maxClimbs[MAXPLAYERS+1] = {0, ...};
new bool:gClimb[MAXPLAYERS+1][9];
new bool:justClimbed[MAXPLAYERS+1] = {false, ...};
new bool:blockClimb[MAXPLAYERS+1] = {false, ...};

//Pyro airblast jump code begins here

new Handle:sm_tf2paj_enabled = INVALID_HANDLE;
new Handle:tf_flamethrower_burst_zvelocity = INVALID_HANDLE;

new bool:bPluginEnabled = true;
new Float:flZVelocity = 0.0;

new Float:flNextSecondaryAttack[MAXPLAYERS+1];

new Handle:fwOnPyroAirBlast = INVALID_HANDLE;

public Plugin:myinfo = {
	name		= "Player Movement",
	author		= "Nanochip/Leonardo/Hombre",
	description = "Melee Wall Climbing & Airblast Jumping plugins merged for better performance",
	version		= PLUGIN_VERSION,
};

public APLRes:AskPluginLoad2(Handle:hMySelf, bool:bLate, String:strError[], iMaxErrors)
{
    RegPluginLibrary( "tf2pyroairjump" );
    return APLRes_Success;
}

public OnConfigsExecuted()
{
    bPluginEnabled = GetConVarBool( sm_tf2paj_enabled );
    for( new i = 1; i <= MaxClients; i++ )
        if( IsValidClient( i ) )
        {
            SDKUnhook( i, SDKHook_PreThink, OnPreThink );
        }
    flZVelocity = GetConVarFloat( tf_flamethrower_burst_zvelocity );
}

public OnClientPutInServer( iClient )
{
    flNextSecondaryAttack[iClient] = GetGameTime();
    SDKHook( iClient, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost );
}

public OnPluginStart()
{
	CreateConVar("sm_playerclimb_version", PLUGIN_VERSION, "Player Climb Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvarEnable = CreateConVar("sm_playerclimb_enable", "1", "Enable the plugin? 1 = Yes, 0 = No.", _, true, 0.0, true, 1.0);
	cvarDamageAmount = CreateConVar("sm_playerclimb_damageamount", "5.0", "How much damage should a player take on each melee climb?");
	cvarTeam = CreateConVar("sm_playerclimb_team", "0", "Restrict climbing to X team only. 0 = No restriction, 1 = BLU, 2 = RED.", _, true, 0.0, true, 2.0);
	cvarMaxClimbs = CreateConVar("sm_playerclimb_maxclimbs", "0.0", "The maximum amount of times the player can melee the wall (climb) while being in the air before they have to touch the ground again. 0 = Disabled, 1 = 1 Climb... 23 = 23 Climbs.");
	cvarCooldown = CreateConVar("sm_playerclimb_cooldown", "0.0", "Time in seconds before the player may climb the wall again, this cooldown starts when the player touches the ground after climbing.");
	cvarNextClimb = CreateConVar("sm_playerclimb_nextclimb", "1.56", "Time in seconds in between melee climbs", _, true, 0.1);
	
	for (new i = 1; i <= MaxClients; i++)
	{
		for (new col = 0; col < 9; col++)
		{
			gClimb[i][col] = true;
		}
	}
	//Pyro airblast jump code begins here
    
    sm_tf2paj_enabled = CreateConVar("sm_tf2paj_enabled", "1", "", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
    
    decl String:strGameDir[8];
    GetGameFolderName( strGameDir, sizeof(strGameDir) );
    if( !StrEqual( strGameDir, "tf", false ) && !StrEqual( strGameDir, "tf_beta", false ) )
        SetFailState( "THIS PLUGIN IS FOR TEAM FORTRESS 2 ONLY!" );
    
    tf_flamethrower_burst_zvelocity = FindConVar( "tf_flamethrower_burst_zvelocity" );
    
    fwOnPyroAirBlast = CreateGlobalForward( "TF2_OnPyroAirBlast", ET_Event, Param_Cell );
    
    for( new i = 0; i <= MAXPLAYERS; i++ )
    {
        flNextSecondaryAttack[i] = GetGameTime();
        if( IsValidClient(i) )
        {
            SDKHook( i, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost );
        }
    }
}

public OnClientDisconnect(client)
{
	justClimbed[client] = false;
	blockClimb[client] = false;
	maxClimbs[client] = 0;
}

public OnWeaponSwitchPost( iClient, iWeapon )
{
    if( !IsValidClient(iClient) || !IsPlayerAlive(iClient) || !IsValidEntity(iWeapon) )
        return;
    
    decl String:strClassname[64];
    GetEntityClassname( iWeapon, strClassname, sizeof(strClassname) );
    if( !StrEqual( strClassname, "tf_weapon_flamethrower", false ) && !StrEqual( strClassname, "tf_weapon_rocketlauncher_fireball", false ))
        return;
    
    flNextSecondaryAttack[iClient] = GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" );
}

public OnClientAuthorized(client, const String:auth[])
{
	if (!GetConVarBool(cvarEnable)) return;
	for (new i = 1; i <= MaxClients; i++)
	{
		for (new col = 0; col < 9; col++)
		{
			gClimb[i][col] = true;
		}
	}
}

public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	if (!GetConVarBool(cvarEnable) || !IsValidClient(client)) return Plugin_Continue;
	
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Scout:		if (!gClimb[client][0]) return Plugin_Continue;
		case TFClass_Soldier:		if (!gClimb[client][1]) return Plugin_Continue;
		case TFClass_Pyro:		if (!gClimb[client][2]) return Plugin_Continue;
		case TFClass_DemoMan:		if (!gClimb[client][3]) return Plugin_Continue;
		case TFClass_Heavy:		if (!gClimb[client][4]) return Plugin_Continue;
		case TFClass_Engineer:	if (!gClimb[client][5]) return Plugin_Continue;
		case TFClass_Medic:		if (!gClimb[client][6]) return Plugin_Continue;
		case TFClass_Sniper:		if (!gClimb[client][7]) return Plugin_Continue;
		case TFClass_Spy:		if (!gClimb[client][8]) return Plugin_Continue;
	}
	
	if (!CheckCommandAccess(client, "sm_playerclimb_override", 0, true)) return Plugin_Continue;
	
	if (GetConVarInt(cvarTeam) != 0)
	{
		new team;
		if (GetConVarInt(cvarTeam) == 1) team = 3;
		if (GetConVarInt(cvarTeam) == 2) team = 2;
		if (GetClientTeam(client) != team) return Plugin_Continue;
	}
	
	if (IsValidEntity(weapon))
	{
		if (TF2_GetPlayerMaxHealth(client) == 140)
		{
			if (weapon == GetPlayerWeaponSlot(client, TFWeaponSlot_Melee))
			{
				SickleClimbWalls(client, weapon);
			}
		}
	}
	return Plugin_Continue;
}

public Timer_NoAttacking(any:ref)
{
	new weapon = EntRefToEntIndex(ref);
	SetNextAttack(weapon, GetConVarFloat(cvarNextClimb));
}

public void OnGameFrame()
{
    float cooldown = GetConVarFloat(cvarCooldown); // Cache convar value once per frame
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;
			
		if (IsValidClient(i))
			OnPreThink( i );

        if ((GetEntityFlags(i) & FL_ONGROUND) == 0)
            continue;

        maxClimbs[i] = 0;

        if (cooldown > 0.0 && justClimbed[i])
        {
            justClimbed[i] = false;
            blockClimb[i] = true;
            CreateTimer(cooldown, Timer_ClimbCooldown, i, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public OnPreThink( iClient )
{
    if( !IsPlayerAlive(iClient) )
        return;
    
    if( TF2_GetPlayerClass(iClient) != TFClass_Pyro )
        return;
    
    //this was in the original copy, not sure how much has changed since it was last updated but this part seems unecessary
    //I personally commented it out to avoid the "Entity 1 (class 'player') reported ENTITY_CHANGE_NONE but 'm_nNextThinkTick' changed."
    //spam in the console
    
    //new iNextTickTime = RoundToNearest( FloatDiv( GetGameTime() , GetTickInterval() ) ) + 5;
    //SetEntProp( iClient, Prop_Data, "m_nNextThinkTick", iNextTickTime );
    
    new Float:flSpeed = GetEntPropFloat( iClient, Prop_Send, "m_flMaxspeed" );
    if( flSpeed > 0.0 && flSpeed < 5.0 )
        return;
    
    if( GetEntProp( iClient, Prop_Data, "m_nWaterLevel" ) > 1 )
        return;
    
    if(!(GetClientButtons(iClient) & IN_ATTACK2))
    {
        return;
    }

    new iWeapon = GetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon" );
    if( !IsValidEntity(iWeapon) )
        return;
    
    decl String:strClassname[64];
    GetEntityClassname( iWeapon, strClassname, sizeof(strClassname) );
    
    if( !StrEqual( strClassname, "tf_weapon_rocketlauncher_fireball", false ))
        return;

    if( ( GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" ) - flNextSecondaryAttack[iClient] ) <= 0.0 )
        return;
    flNextSecondaryAttack[iClient] = GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" );
    
    //PrintToChat( iClient, "%0.1f", GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" ) - flNextSecondaryAttack[iClient] );
    //PrintToChat( iClient, "%0.1f %0.1f %0.1f", GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" ), flNextSecondaryAttack[iClient], GetGameTime() );
    
    decl Action:result;
    Call_StartForward( fwOnPyroAirBlast );
    Call_PushCell( iClient );
    Call_Finish( result );
    if( result == Plugin_Handled || result == Plugin_Stop )
        return;
    
    if( (GetEntityFlags(iClient) & FL_ONGROUND) == FL_ONGROUND )
        return;
    
    if( !bPluginEnabled )
        return;
    
    decl Float:vecAngles[3], Float:vecVelocity[3];
    GetClientEyeAngles( iClient, vecAngles );
    GetEntPropVector( iClient, Prop_Data, "m_vecVelocity", vecVelocity );
    vecAngles[0] = DegToRad( -1.0 * vecAngles[0] );
    vecAngles[1] = DegToRad( vecAngles[1] );
    vecVelocity[0] -= flZVelocity * Cosine( vecAngles[0] ) * Cosine( vecAngles[1] );
    vecVelocity[1] -= flZVelocity * Cosine( vecAngles[0] ) * Sine( vecAngles[1] );
    vecVelocity[2] -= flZVelocity * Sine( vecAngles[0] );
    TeleportEntity( iClient, NULL_VECTOR, NULL_VECTOR, vecVelocity );
}

public Action:Timer_ClimbCooldown(Handle:timer, any:client)
{
	blockClimb[client] = false;
}

SickleClimbWalls(client, weapon)	 //Credit to Mecha the Slag
{
	if (!IsValidClient(client) || (GetClientHealth(client) <= GetConVarFloat(cvarDamageAmount))) return;
	
	decl String:classname[64];
	decl Float:vecClientEyePos[3], Float:vecClientEyeAng[3];
	GetClientEyePosition(client, vecClientEyePos);	 // Get the position of the player's eyes
	GetClientEyeAngles(client, vecClientEyeAng);	   // Get the angle the player is looking
	
	//Check for colliding entities
	TR_TraceRayFilter(vecClientEyePos, vecClientEyeAng, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client);
	
	if (!TR_DidHit(INVALID_HANDLE)) return;
	
	new TRIndex = TR_GetEntityIndex(INVALID_HANDLE);
	GetEdictClassname(TRIndex, classname, sizeof(classname));
	if (!((StrStarts(classname, "prop_") && classname[5] != 'p') || StrEqual(classname, "worldspawn"))) return;
	
	decl Float:fNormal[3];
	TR_GetPlaneNormal(INVALID_HANDLE, fNormal);
	GetVectorAngles(fNormal, fNormal);
	
	if (fNormal[0] >= 30.0 && fNormal[0] <= 330.0) return;
	if (fNormal[0] <= -30.0) return;
	
	decl Float:pos[3];
	TR_GetEndPosition(pos);
	new Float:distance = GetVectorDistance(vecClientEyePos, pos);
	
	if (distance >= 100.0) return;
	
	if (blockClimb[client])
	{
		PrintToChat(client, "[SM] Climbing is currently on cool-down, please wait.");
		return;
	}
	
	new maxNumClimbs = GetConVarInt(cvarMaxClimbs);
	
	if (maxNumClimbs != 0 && maxClimbs[client] >= maxNumClimbs && !(GetEntityFlags(client) & FL_ONGROUND))
	{
		PrintToChat(client, "[SM] You need to touch the ground before you can climb again.");
		return;
	}
	
	new Float:fVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
	
	fVelocity[2] = 600.0;
	
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
	
	//SDKHooks_TakeDamage(client, client, client, GetConVarFloat(cvarDamageAmount), DMG_CLUB, 0);
	
	//ClientCommand(client, "playgamesound \"%s\"", "player\\taunt_clip_spin.wav");
	EmitAmbientSound("player/taunt_clip_spin.wav", vecClientEyePos);
	
	RequestFrame(Timer_NoAttacking, EntIndexToEntRef(weapon));
	maxClimbs[client]++;
	justClimbed[client] = true;
}

stock int TF2_GetPlayerMaxHealth(int client) {
	return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}

public bool:TraceRayDontHitSelf(entity, mask, any:data)
{
	return (entity != data);
}

stock SetNextAttack(weapon, Float:duration = 0.0)
{
	if (weapon <= MaxClients || !IsValidEntity(weapon)) return;
	new Float:next = GetGameTime() + duration;
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", next);
	SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", next);
}

stock bool:IsValidClient(iClient)
{
	return (0 < iClient && iClient <= MaxClients && IsClientInGame(iClient));
}

stock bool:StrStarts(const String:szStr[], const String:szSubStr[], bool:bCaseSensitive = true) 
{
	return !StrContains(szStr, szSubStr, bCaseSensitive);
}
