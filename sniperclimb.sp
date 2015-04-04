#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0"

new Handle:cvarDamage

public Plugin:myinfo = {
	name        = "Sniper Climb",
	author      = "Nanochip & VSH Devs",
	description = "Climb walls with sniper melee.",
	version     = PLUGIN_VERSION,
	url         = "http://thecubeserver.org/"
};

public OnPluginStart()
{
	CreateConVar("sm_sniperclimb_version", PLUGIN_VERSION, "Sniper Climb Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvarDamage = CreateConVar("sm_sniperclimb_dmagae", "1.0", "Should a player take damage when climbing walls as a sniper? 1 = Yes 0 = No.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	AutoExecConfig(true, "SniperClimb");
}

public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
    if (!IsValidClient(client)) return Plugin_Continue; // IsValidClient(client, false)

    if (IsValidEntity(weapon))
    {
        new index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
        if (index == 232 && StrEqual(weaponname, "tf_weapon_club", false))
        {
            SickleClimbWalls(client, weapon);
        }
    }
    return Plugin_Continue;
}

public Timer_NoAttacking(any:ref)
{
    new weapon = EntRefToEntIndex(ref);
    SetNextAttack(weapon, 1.56);
}

SickleClimbWalls(client, weapon)     //Credit to Mecha the Slag
{
    if (!IsValidClient(client) || (GetClientHealth(client)<=15) )return;

    decl String:classname[64];
    decl Float:vecClientEyePos[3];
    decl Float:vecClientEyeAng[3];
    GetClientEyePosition(client, vecClientEyePos);   // Get the position of the player's eyes
    GetClientEyeAngles(client, vecClientEyeAng);       // Get the angle the player is looking

    //Check for colliding entities
    TR_TraceRayFilter(vecClientEyePos, vecClientEyeAng, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client);

    if (!TR_DidHit(INVALID_HANDLE)) return;

    new TRIndex = TR_GetEntityIndex(INVALID_HANDLE);
    GetEdictClassname(TRIndex, classname, sizeof(classname));
    if (!StrEqual(classname, "worldspawn")) return;

    decl Float:fNormal[3];
    TR_GetPlaneNormal(INVALID_HANDLE, fNormal);
    GetVectorAngles(fNormal, fNormal);

    if (fNormal[0] >= 30.0 && fNormal[0] <= 330.0) return;
    if (fNormal[0] <= -30.0) return;

    decl Float:pos[3];
    TR_GetEndPosition(pos);
    new Float:distance = GetVectorDistance(vecClientEyePos, pos);

    if (distance >= 100.0) return;

    new Float:fVelocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);

    fVelocity[2] = 600.0;

    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
	
	if (GetConVarBool(cvarDamage))
	{
		SDKHooks_TakeDamage(client, client, client, 15.0, DMG_CLUB, GetPlayerWeaponSlot(client, TFWeaponSlot_Melee));
	}
    
    ClientCommand(client, "playgamesound \"%s\"", "player\\taunt_clip_spin.wav");
    
    RequestFrame(Timer_NoAttacking, EntIndexToEntRef(weapon));
}

public bool:TraceRayDontHitSelf(entity, mask, any:data)
{
    return (entity != data);
}

stock SetNextAttack(weapon, Float:duration = 0.0)
{
    if (weapon <= MaxClients) return;
    if (!IsValidEntity(weapon)) return;
    new Float:next = GetGameTime() + duration;
    SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", next);
    SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", next);
}

stock bool:IsValidClient(iClient)
{
    return (0 < iClient && iClient <= MaxClients && IsClientInGame(iClient));
}
