// Super Tanks++: Clone Ability
#include <st_clone>
#define REQUIRE_PLUGIN
#include <super_tanks++>
#undef REQUIRE_PLUGIN
#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "[ST++] Clone Ability",
	author = ST_AUTHOR,
	description = "The Super Tank creates clones of itself.",
	version = ST_VERSION,
	url = ST_URL
};

bool g_bCloned[MAXPLAYERS + 1], g_bTankConfig[ST_MAXTYPES + 1];
int g_iCloneAbility[ST_MAXTYPES + 1], g_iCloneAbility2[ST_MAXTYPES + 1], g_iCloneAmount[ST_MAXTYPES + 1], g_iCloneAmount2[ST_MAXTYPES + 1], g_iCloneChance[ST_MAXTYPES + 1], g_iCloneChance2[ST_MAXTYPES + 1], g_iCloneCount[MAXPLAYERS + 1], g_iCloneHealth[ST_MAXTYPES + 1], g_iCloneHealth2[ST_MAXTYPES + 1], g_iCloneMessage[ST_MAXTYPES + 1], g_iCloneMessage2[ST_MAXTYPES + 1], g_iCloneMode[ST_MAXTYPES + 1], g_iCloneMode2[ST_MAXTYPES + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!bIsValidGame(false) && !bIsValidGame())
	{
		strcopy(error, err_max, "[ST++] Clone Ability only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	CreateNative("ST_CloneAllowed", aNative_CloneAllowed);
	RegPluginLibrary("st_clone");
	return APLRes_Success;
}

public any aNative_CloneAllowed(Handle plugin, int numParams)
{
	int iTank = GetNativeCell(1);
	bool bCloneInstalled = GetNativeCell(2);
	if (ST_TankAllowed(iTank) && bIsCloneAllowed(iTank, bCloneInstalled))
	{
		return true;
	}
	return false;
}

public void OnPluginStart()
{
	LoadTranslations("super_tanks++.phrases");
}

public void OnMapStart()
{
	vReset();
}

public void OnClientPutInServer(int client)
{
	g_bCloned[client] = false;
	g_iCloneCount[client] = 0;
}

public void OnMapEnd()
{
	vReset();
}

public void ST_Configs(const char[] savepath, bool main)
{
	KeyValues kvSuperTanks = new KeyValues("Super Tanks++");
	kvSuperTanks.ImportFromFile(savepath);
	for (int iIndex = ST_MinType(); iIndex <= ST_MaxType(); iIndex++)
	{
		char sName[MAX_NAME_LENGTH + 1];
		Format(sName, sizeof(sName), "Tank #%d", iIndex);
		if (kvSuperTanks.JumpToKey(sName))
		{
			main ? (g_bTankConfig[iIndex] = false) : (g_bTankConfig[iIndex] = true);
			main ? (g_iCloneAbility[iIndex] = kvSuperTanks.GetNum("Clone Ability/Ability Enabled", 0)) : (g_iCloneAbility2[iIndex] = kvSuperTanks.GetNum("Clone Ability/Ability Enabled", g_iCloneAbility[iIndex]));
			main ? (g_iCloneAbility[iIndex] = iClamp(g_iCloneAbility[iIndex], 0, 1)) : (g_iCloneAbility2[iIndex] = iClamp(g_iCloneAbility2[iIndex], 0, 1));
			main ? (g_iCloneMessage[iIndex] = kvSuperTanks.GetNum("Clone Ability/Ability Message", 0)) : (g_iCloneMessage2[iIndex] = kvSuperTanks.GetNum("Clone Ability/Ability Message", g_iCloneMessage[iIndex]));
			main ? (g_iCloneMessage[iIndex] = iClamp(g_iCloneMessage[iIndex], 0, 1)) : (g_iCloneMessage2[iIndex] = iClamp(g_iCloneMessage2[iIndex], 0, 1));
			main ? (g_iCloneAmount[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Amount", 2)) : (g_iCloneAmount2[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Amount", g_iCloneAmount[iIndex]));
			main ? (g_iCloneAmount[iIndex] = iClamp(g_iCloneAmount[iIndex], 1, 25)) : (g_iCloneAmount2[iIndex] = iClamp(g_iCloneAmount2[iIndex], 1, 25));
			main ? (g_iCloneChance[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Chance", 4)) : (g_iCloneChance2[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Chance", g_iCloneChance[iIndex]));
			main ? (g_iCloneChance[iIndex] = iClamp(g_iCloneChance[iIndex], 1, 9999999999)) : (g_iCloneChance2[iIndex] = iClamp(g_iCloneChance2[iIndex], 1, 9999999999));
			main ? (g_iCloneHealth[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Health", 1000)) : (g_iCloneHealth2[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Health", g_iCloneHealth[iIndex]));
			main ? (g_iCloneHealth[iIndex] = iClamp(g_iCloneHealth[iIndex], 1, ST_MAXHEALTH)) : (g_iCloneHealth2[iIndex] = iClamp(g_iCloneHealth2[iIndex], 1, ST_MAXHEALTH));
			main ? (g_iCloneMode[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Mode", 0)) : (g_iCloneMode2[iIndex] = kvSuperTanks.GetNum("Clone Ability/Clone Mode", g_iCloneMode[iIndex]));
			main ? (g_iCloneMode[iIndex] = iClamp(g_iCloneMode[iIndex], 0, 1)) : (g_iCloneMode2[iIndex] = iClamp(g_iCloneMode2[iIndex], 0, 1));
			kvSuperTanks.Rewind();
		}
	}
	delete kvSuperTanks;
}

public void ST_PluginEnd()
{
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (g_bCloned[iPlayer])
		{
			IsFakeClient(iPlayer) ? KickClient(iPlayer) : ForcePlayerSuicide(iPlayer);
		}
	}
}

public void ST_Event(Event event, const char[] name)
{
	if (StrEqual(name, "player_death"))
	{
		int iTankId = event.GetInt("userid"), iTank = GetClientOfUserId(iTankId);
		if (iCloneAbility(iTank) == 1 && ST_TankAllowed(iTank))
		{
			g_iCloneCount[iTank] = 0;
		}
	}
}

public void ST_Ability(int tank)
{
	int iCloneChance = !g_bTankConfig[ST_TankType(tank)] ? g_iCloneChance[ST_TankType(tank)] : g_iCloneChance2[ST_TankType(tank)];
	if (iCloneAbility(tank) == 1 && GetRandomInt(1, iCloneChance) == 1 && ST_TankAllowed(tank) && IsPlayerAlive(tank) && !g_bCloned[tank])
	{
		int iCloneAmount = !g_bTankConfig[ST_TankType(tank)] ? g_iCloneAmount[ST_TankType(tank)] : g_iCloneAmount2[ST_TankType(tank)],
			iCloneMessage = !g_bTankConfig[ST_TankType(tank)] ? g_iCloneMessage[ST_TankType(tank)] : g_iCloneMessage2[ST_TankType(tank)];
		if (g_iCloneCount[tank] < iCloneAmount)
		{
			float flHitPosition[3], flPosition[3], flAngles[3], flVector[3];
			GetClientEyePosition(tank, flPosition);
			GetClientEyeAngles(tank, flAngles);
			flAngles[0] = -25.0;
			GetAngleVectors(flAngles, flAngles, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(flAngles, flAngles);
			ScaleVector(flAngles, -1.0);
			vCopyVector(flAngles, flVector);
			GetVectorAngles(flAngles, flAngles);
			Handle hTrace = TR_TraceRayFilterEx(flPosition, flAngles, MASK_SOLID, RayType_Infinite, bTraceRayDontHitSelf, tank);
			if (TR_DidHit(hTrace))
			{
				TR_GetEndPosition(flHitPosition, hTrace);
				NormalizeVector(flVector, flVector);
				ScaleVector(flVector, -40.0);
				AddVectors(flHitPosition, flVector, flHitPosition);
				float flDistance = GetVectorDistance(flHitPosition, flPosition);
				if (flDistance < 200.0 && flDistance > 40.0)
				{
					bool bTankBoss[MAXPLAYERS + 1];
					for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
					{
						bTankBoss[iPlayer] = false;
						if (ST_TankAllowed(iPlayer) && IsPlayerAlive(iPlayer))
						{
							bTankBoss[iPlayer] = true;
						}
					}
					ST_SpawnTank(tank, ST_TankType(tank));
					int iSelectedType;
					for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
					{
						if (ST_TankAllowed(iPlayer) && IsPlayerAlive(iPlayer) && !bTankBoss[iPlayer])
						{
							iSelectedType = iPlayer;
							break;
						}
					}
					if (iSelectedType > 0)
					{
						TeleportEntity(iSelectedType, flHitPosition, NULL_VECTOR, NULL_VECTOR);
						g_bCloned[iSelectedType] = true;
						int iCloneHealth = !g_bTankConfig[ST_TankType(tank)] ? g_iCloneHealth[ST_TankType(tank)] : g_iCloneHealth2[ST_TankType(tank)],
							iNewHealth = (iCloneHealth > ST_MAXHEALTH) ? ST_MAXHEALTH : iCloneHealth;
						SetEntityHealth(iSelectedType, iNewHealth);
						g_iCloneCount[tank]++;
						if (iCloneMessage == 1)
						{
							char sTankName[MAX_NAME_LENGTH + 1];
							ST_TankName(tank, sTankName);
							PrintToChatAll("%s %t", ST_PREFIX2, "Clone", sTankName);
						}
					}
				}
			}
			delete hTrace;
		}
	}
}

public void ST_BossStage(int tank)
{
	if (iCloneAbility(tank) == 1 && ST_TankAllowed(tank) && !g_bCloned[tank])
	{
		g_iCloneCount[tank] = 0;
	}
}

stock void vReset()
{
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (bIsValidClient(iPlayer))
		{
			g_bCloned[iPlayer] = false;
			g_iCloneCount[iPlayer] = 0;
		}
	}
}

stock bool bIsCloneAllowed(int tank, bool clone)
{
	int iCloneMode = !g_bTankConfig[ST_TankType(tank)] ? g_iCloneMode[ST_TankType(tank)] : g_iCloneMode2[ST_TankType(tank)];
	if (clone && iCloneMode == 0 && g_bCloned[tank])
	{
		return false;
	}
	return true;
}

stock int iCloneAbility(int tank)
{
	return !g_bTankConfig[ST_TankType(tank)] ? g_iCloneAbility[ST_TankType(tank)] : g_iCloneAbility2[ST_TankType(tank)];
}