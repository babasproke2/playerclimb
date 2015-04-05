#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <clientprefs>

#define PLUGIN_VERSION "1.2"

new Handle:cvarEnable;
new Handle:cvarDamageAmount;
new Handle:cvarTeam;
new Handle:cvarBoss;
new Handle:cvarClass;

new Handle:hCookieClimb;
new bool:gClimb[MAXPLAYERS+1];

public Plugin:myinfo = {
	name        = "Player Climb",
	author      = "Nanochip",
	description = "Climb walls with melee attack.",
	version     = PLUGIN_VERSION,
	url         = "http://thecubeserver.org/"
};

public OnPluginStart()
{
	CreateConVar("sm_playerclimb_version", PLUGIN_VERSION, "Player Climb Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvarEnable = CreateConVar("sm_playerclimb_enable", "1", "Enable the plugin? 1 = Yes, 0 = No.", FCVAR_NOTIFY);
	cvarDamageAmount = CreateConVar("sm_playerclimb_damageamount", "15.0", "How much damage should a player take on each melee climb?", FCVAR_NOTIFY);
	cvarTeam = CreateConVar("sm_playerclimb_team", "0", "Restrict climbing to X team only. 0 = No restriction, 1 = BLU, 2 = RED.", FCVAR_NOTIFY);
	cvarBoss = CreateConVar("sm_playerclimb_boss", "0", "Should bosses (VSH/FF2) be allowed to climb? 0 = No, 1 = Yes.", FCVAR_NOTIFY);
	cvarClass = CreateConVar("sm_playerclimb_class", "sniper", "Which classes should be allowed to climb? You can add multiple classes by separating them with a comma (EX: scout,sniper,spy,heavy,soldier,demo,medic,pyro,engineer). For all classes, just put \"all\" (no quotes).", FCVAR_NOTIFY);
	
	hCookieClimb = RegClientCookie("sm_playerclimb_cookie", "Toggle playerclimb", CookieAccess_Private); 
	
	AutoExecConfig(true, "PlayerClimb");
	
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i)) gClimb[i] = true;
	}
	
	for(new i = 1; i <= MaxClients; i++) if(IsClientInGame(i))
	{
		if(AreClientCookiesCached(i))
			OnClientCookiesCached(i);
	}
	
	SetCookieMenuItem(PlayerClimbHandler, 0, "Player Climb Toggle");
}

public PlayerClimbHandler(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
    if (action == CookieMenuAction_SelectOption)
    {
        CreatePlayerClimbMenu(client);
    }
}

CreatePlayerClimbMenu(client)
{
    new Handle:menu = CreateMenu(CreatePlayerClimbMenuCallback);
    SetMenuTitle(menu, "Player Climb Toggle");
	
    if (gClimb[client])
        AddMenuItem(menu, "false", "Disable climbing.");
	else
	    AddMenuItem(menu, "true", "Enable climbing.");
	
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public CreatePlayerClimbMenuCallback(Handle:menu, MenuAction:action, client, param2)
{
    if(action == MenuAction_End) CloseHandle(menu);

    if(action == MenuAction_Select)
    {
	    decl String:info[10];
	    GetMenuItem(menu, param2, info, sizeof(info));
	    SetClientCookie(client, hCookieClimb, info);
	    if (StrEqual(info, "true")) 
		{
            gClimb[client] = true;
            PrintToChat(client, "[SM] Enabled climbing.");
		}
	    if (StrEqual(info, "false"))
		{
            gClimb[client] = false;
            PrintToChat(client, "[SM] Disabled climbing.");
	    }
    }
}

public OnClientAuthorized(client, const String:auth[])
{
    gClimb[client] = true;
}

public OnClientCookiesCached(client)
{
	decl String:strCookieClimb[10];
	GetClientCookie(client, hCookieClimb, strCookieClimb, sizeof(strCookieClimb));
	if (StrEqual(strCookieClimb, "false")) gClimb[client] = false;
	if (StrEqual(strCookieClimb, "true")) gClimb[client] = true;
}

public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
    if (!GetConVarBool(cvarEnable)) return Plugin_Continue;
    if (!IsValidClient(client)) return Plugin_Continue;
    if (!gClimb[client]) return Plugin_Continue;

    if (!CheckCommandAccess(client, "sm_playerclimb_override", 0, true)) return Plugin_Continue;

    new bool:iBoss = false;
    if (!GetConVarBool(cvarBoss))
    {
        if(IsClientBoss(client)) return Plugin_Continue;
    } else {
        iBoss = IsClientBoss(client);
    }

    if (GetConVarInt(cvarTeam) != 0)
    {
		new team;
		if (GetConVarInt(cvarTeam) == 1) team = 3;
		if (GetConVarInt(cvarTeam) == 2) team = 2;
		if (GetClientTeam(client) != team) return Plugin_Continue;
	}
	
    if (IsValidEntity(weapon))
    {
        if (weapon == GetPlayerWeaponSlot(client, TFWeaponSlot_Melee) && (IsClassAllowed(client) || iBoss))
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
    if (!GetConVarBool(cvarEnable)) return;
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
    if (!((StrStarts(classname, "prop_") && classname[5] != 'p') || StrEqual(classname, "worldspawn"))) 
    { 
        return; 
    } 

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
	
    SDKHooks_TakeDamage(client, client, client, GetConVarFloat(cvarDamageAmount), DMG_CLUB, 0);
	
    ClientCommand(client, "playgamesound \"%s\"", "player\\taunt_clip_spin.wav");
    
    RequestFrame(Timer_NoAttacking, EntIndexToEntRef(weapon));
}

public bool:TraceRayDontHitSelf(entity, mask, any:data)
{
    return (entity != data);
}

stock bool:IsClientBoss(client)
{
	return GetClientHealth(client) >= 600;
}

stock bool:IsClassAllowed(client)
{
	new String:cvClass[255];
	GetConVarString(cvarClass, cvClass, sizeof(cvClass));
	if (StrEqual(cvClass, "all", false)) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Scout && StrContains(cvClass, "scout", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Sniper && StrContains(cvClass, "sniper", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Soldier && StrContains(cvClass, "soldier", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_DemoMan && StrContains(cvClass, "demo", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Medic && StrContains(cvClass, "medic", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Heavy && StrContains(cvClass, "heavy", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Pyro && StrContains(cvClass, "pyro", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Spy && StrContains(cvClass, "spy", false) != -1) return true;
	if (TF2_GetPlayerClass(client) == TFClass_Engineer && StrContains(cvClass, "engineer", false) != -1) return true;
	return false;
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

stock bool:StrStarts(const String:szStr[], const String:szSubStr[], bool:bCaseSensitive = true) 
{ 
    return !StrContains(szStr, szSubStr, bCaseSensitive); 
} 
