#pragma semicolon 1

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#include <smlib>

#define MAX_AMMO 14

public Plugin myinfo = {
	name = "Cykar Blast",
	author = PLUGIN_AUTHOR,
	description = "Blast bullets from Road Rager taunt's car-mounted gun",
	version = PLUGIN_VERSION,
	url = "https://github.com/geominorai/cykarblast"
};

enum struct Blast {
	Handle hTimer;
	DataPack hDataPack;
}

ConVar g_hCVBulletSpread;
ConVar g_hCVBulletDamage;
ConVar g_hCVCritChance;

ConVar g_hCVFriendlyFire;

int g_iParticleIndex[6];

Blast g_eBlast[MAXPLAYERS+1];

public void OnPluginStart() {
	CreateConVar("sm_cykarblast_version", PLUGIN_VERSION, "Cykar Blast version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hCVBulletSpread = CreateConVar("sm_cykarblast_bullet_spread", "0.04", "Bullet base spread", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVBulletDamage = CreateConVar("sm_cykarblast_bullet_damage", "15.0", "Bullet base damage", FCVAR_NONE, true, 0.0, false);
	g_hCVCritChance = CreateConVar("sm_cykarblast_crit_chance", "0.04", "Bullet critical change", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hCVFriendlyFire = FindConVar("mp_friendlyfire");

	AutoExecConfig(true);
}

public void OnMapStart() {
	CacheParticleIndices();
}

public void OnMapEnd() {
	for (int i=1; i<=MaxClients; i++) {
		ResetClient(i);
	}
}

public void OnClientDisconnect(int iClient) {
	ResetClient(iClient);
}

public void OnEntityCreated(int iEntity, const char[] sClassName) {
	if (StrEqual(sClassName, "instanced_scripted_scene", false)) {
		SDKHook(iEntity, SDKHook_SpawnPost, SDKHookCB_SpawnTaunt);
	}
}

public void TF2_OnConditionRemoved(int iClient, TFCond iCondition) {
	if (iCondition == TFCond_Taunting) {
		ResetClient(iClient);
	}
}

// Custom callbacks

public void SDKHookCB_SpawnTaunt(int iEntity) {
	char sSceneFile[PLATFORM_MAX_PATH];
	GetEntPropString(iEntity, Prop_Data, "m_iszSceneFile", sSceneFile, sizeof(sSceneFile));

	int iOwner = GetEntPropEnt(iEntity, Prop_Data, "m_hOwner");

	if (StrEqual(sSceneFile, "scenes/workshop/player/heavy/low/taunt_the_road_rager_outro.vcd")) {
		ResetClient(iOwner);
		return;
	}

	if (!StrEqual(sSceneFile, "scenes/workshop/player/heavy/low/taunt_the_road_rager_a1.vcd")) {
		return;
	}

	DataPack hDataPack = new DataPack();
	hDataPack.WriteCell(GetClientSerial(iOwner));
	hDataPack.WriteCell(MAX_AMMO);

	g_eBlast[iOwner].hTimer = CreateTimer(1.2, Timer_Fire, hDataPack, TIMER_FLAG_NO_MAPCHANGE);
	g_eBlast[iOwner].hDataPack = hDataPack;
}

public bool TraceEntityFilter_Clients(int iEntity, int iContentsMask, int iClient) {
	return 1 <= iEntity <= MaxClients && iEntity != iClient && (g_hCVFriendlyFire.BoolValue || TF2_GetClientTeam(iEntity) != TF2_GetClientTeam(iClient));
}

// Timers

public Action Timer_Fire(Handle hTimer, DataPack hDataPack) {
	hDataPack.Reset();

	int iClient = GetClientFromSerial(hDataPack.ReadCell());
	if (!iClient) {
		delete g_eBlast[iClient].hDataPack;
		g_eBlast[iClient].hTimer = null;
		return Plugin_Handled;
	}

	DataPackPos eAmmoPos = hDataPack.Position;
	int iAmmo = hDataPack.ReadCell();
	if (iAmmo == MAX_AMMO) {
		FireBullet(iClient);

		hDataPack.Position = eAmmoPos;
		hDataPack.WriteCell(iAmmo-1);

		g_eBlast[iClient].hTimer = CreateTimer(0.1, Timer_Fire, hDataPack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

		return Plugin_Handled;
	}

	if (!iAmmo) {
		delete g_eBlast[iClient].hDataPack;
		g_eBlast[iClient].hTimer = null;
		return Plugin_Stop;
	}

	FireBullet(iClient);

	hDataPack.Position = eAmmoPos;
	hDataPack.WriteCell(iAmmo-1);

	return Plugin_Continue;
}

// Helpers

void CacheParticleIndices() {
	int iTableIdx = FindStringTable("ParticleEffectNames");
	if (iTableIdx == INVALID_STRING_TABLE) {
		SetFailState("Cannot find ParticleEffectNames string table");
	}

	g_iParticleIndex[0] = FindStringIndex(iTableIdx, "bullet_tracer01_red");
	g_iParticleIndex[1] = FindStringIndex(iTableIdx, "bullet_tracer01_blue");
	g_iParticleIndex[2] = FindStringIndex(iTableIdx, "bullet_tracer01_red_crit");
	g_iParticleIndex[3] = FindStringIndex(iTableIdx, "bullet_tracer01_blue_crit");
	g_iParticleIndex[4] = FindStringIndex(iTableIdx, "blood_impact_red_01");
	g_iParticleIndex[5] = FindStringIndex(iTableIdx, "impact_concrete");
}

void FireBullet(int iClient) {
	float vecPos[3], vecAng[3];
	Entity_GetAbsOrigin(iClient, vecPos);
	Entity_GetAbsAngles(iClient, vecAng);

	float vecForward[3];
	GetAngleVectors(vecAng, vecForward, NULL_VECTOR, NULL_VECTOR);

	vecPos[2] += 35.0;

	float fAngSpread = RadToDeg(ArcSine(g_hCVBulletSpread.FloatValue));

	vecAng[0] += GetRandomFloat(-fAngSpread, fAngSpread);
	vecAng[1] += GetRandomFloat(-fAngSpread, fAngSpread);

	TR_TraceRayFilter(vecPos, vecAng, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilter_Clients, iClient);
	if (!TR_DidHit()) {
		return;
	}

	float vecEndPos[3];
	TR_GetEndPosition(vecEndPos);

	ScaleVector(vecForward, 60.0);
	AddVectors(vecPos, vecForward, vecPos);

	TFTeam eTeam = TF2_GetClientTeam(iClient);
	bool bCritical = GetURandomFloat() < g_hCVCritChance.FloatValue;

	int iTrackerParticleIdx = g_iParticleIndex[view_as<int>(eTeam == TFTeam_Blue) | (view_as<int>(bCritical) << 1)];

	TE_Start("TFParticleEffect");

	TE_WriteFloat("m_vecStart[0]", vecEndPos[0]);
	TE_WriteFloat("m_vecStart[1]", vecEndPos[1]);
	TE_WriteFloat("m_vecStart[2]", vecEndPos[2]);
	TE_WriteFloat("m_vecOrigin[0]", vecPos[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecPos[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecPos[2]);
	TE_WriteNum("m_iParticleSystemIndex", iTrackerParticleIdx);

	TE_SendToAll();

	TE_Start("TFParticleEffect");

	TE_WriteFloat("m_vecOrigin[0]", vecEndPos[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecEndPos[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecEndPos[2]);

	int iHitEntity = TR_GetEntityIndex();
	if (iHitEntity) {
		TE_WriteNum("m_iParticleSystemIndex", g_iParticleIndex[4]);

		int iInflictor = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
		if (iInflictor == -1) {
			iInflictor = 0;
		}

		int iDamageFlags = DMG_BULLET | DMG_USEDISTANCEMOD;
		if (bCritical) {
			iDamageFlags |= DMG_CRIT;
		}

		SDKHooks_TakeDamage(iHitEntity, iInflictor, iClient, g_hCVBulletDamage.FloatValue, iDamageFlags);
	} else {
		TE_WriteNum("m_iParticleSystemIndex", g_iParticleIndex[5]);
	}

	TE_SendToAll();
}

void ResetClient(int iClient) {
	delete g_eBlast[iClient].hTimer;
	delete g_eBlast[iClient].hDataPack;
}
