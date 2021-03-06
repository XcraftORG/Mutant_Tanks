/**
 * Mutant Tanks: a L4D/L4D2 SourceMod Plugin
 * Copyright (C) 2020  Alfred "Crasher_3637/Psyk0tik" Llagas
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

#include <sourcemod>
#include <sdkhooks>
#include <mutant_tanks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "[MT] Shake Ability",
	author = MT_AUTHOR,
	description = "The Mutant Tank shakes the survivors' screens.",
	version = MT_VERSION,
	url = MT_URL
};

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!bIsValidGame(false) && !bIsValidGame())
	{
		strcopy(error, err_max, "\"[MT] Shake Ability\" only supports Left 4 Dead 1 & 2.");

		return APLRes_SilentFailure;
	}

	g_bLateLoad = late;

	return APLRes_Success;
}

#define SOUND_SMASH2 "player/charger/hit/charger_smash_02.wav" // Only available in L4D2
#define SOUND_SMASH1 "player/tank/hit/hulk_punch_1.wav"

#define MT_MENU_SHAKE "Shake Ability"

enum struct esPlayer
{
	bool g_bAffected;
	bool g_bFailed;
	bool g_bNoAmmo;

	float g_flShakeChance;
	float g_flShakeDeathChance;
	float g_flShakeDeathRange;
	float g_flShakeInterval;
	float g_flShakeRange;
	float g_flShakeRangeChance;

	int g_iAccessFlags;
	int g_iCooldown;
	int g_iCount;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iImmunityFlags;
	int g_iOwner;
	int g_iShakeAbility;
	int g_iShakeDeath;
	int g_iShakeDuration;
	int g_iShakeEffect;
	int g_iShakeHit;
	int g_iShakeHitMode;
	int g_iShakeMessage;
	int g_iTankType;
}

esPlayer g_esPlayer[MAXPLAYERS + 1];

enum struct esAbility
{
	float g_flShakeChance;
	float g_flShakeDeathChance;
	float g_flShakeDeathRange;
	float g_flShakeInterval;
	float g_flShakeRange;
	float g_flShakeRangeChance;

	int g_iAccessFlags;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iImmunityFlags;
	int g_iShakeAbility;
	int g_iShakeDeath;
	int g_iShakeDuration;
	int g_iShakeEffect;
	int g_iShakeHit;
	int g_iShakeHitMode;
	int g_iShakeMessage;
}

esAbility g_esAbility[MT_MAXTYPES + 1];

enum struct esCache
{
	float g_flShakeChance;
	float g_flShakeDeathChance;
	float g_flShakeDeathRange;
	float g_flShakeInterval;
	float g_flShakeRange;
	float g_flShakeRangeChance;

	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iShakeAbility;
	int g_iShakeDeath;
	int g_iShakeDuration;
	int g_iShakeEffect;
	int g_iShakeHit;
	int g_iShakeHitMode;
	int g_iShakeMessage;
}

esCache g_esCache[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mutant_tanks.phrases");

	RegConsoleCmd("sm_mt_shake", cmdShakeInfo, "View information about the Shake ability.");

	if (g_bLateLoad)
	{
		for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
		{
			if (bIsValidClient(iPlayer, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
			{
				OnClientPutInServer(iPlayer);
			}
		}

		g_bLateLoad = false;
	}
}

public void OnMapStart()
{
	PrecacheSound((bIsValidGame() ? SOUND_SMASH2 : SOUND_SMASH1), true);

	vReset();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	vReset3(client);
}

public void OnClientDisconnect_Post(int client)
{
	vReset3(client);
}

public void OnMapEnd()
{
	vReset();
}

public Action cmdShakeInfo(int client, int args)
{
	if (!MT_IsCorePluginEnabled())
	{
		ReplyToCommand(client, "%s Mutant Tanks\x01 is disabled.", MT_TAG4);

		return Plugin_Handled;
	}

	if (!bIsValidClient(client, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT))
	{
		ReplyToCommand(client, "%s This command is to be used only in-game.", MT_TAG);

		return Plugin_Handled;
	}

	switch (IsVoteInProgress())
	{
		case true: ReplyToCommand(client, "%s %t", MT_TAG2, "Vote in Progress");
		case false: vShakeMenu(client, 0);
	}

	return Plugin_Handled;
}

static void vShakeMenu(int client, int item)
{
	Menu mAbilityMenu = new Menu(iShakeMenuHandler, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	mAbilityMenu.SetTitle("Shake Ability Information");
	mAbilityMenu.AddItem("Status", "Status");
	mAbilityMenu.AddItem("Ammunition", "Ammunition");
	mAbilityMenu.AddItem("Buttons", "Buttons");
	mAbilityMenu.AddItem("Cooldown", "Cooldown");
	mAbilityMenu.AddItem("Details", "Details");
	mAbilityMenu.AddItem("Duration", "Duration");
	mAbilityMenu.AddItem("Human Support", "Human Support");
	mAbilityMenu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int iShakeMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End: delete menu;
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iShakeAbility == 0 ? "AbilityStatus1" : "AbilityStatus2");
				case 1: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityAmmo", g_esCache[param1].g_iHumanAmmo - g_esPlayer[param1].g_iCount, g_esCache[param1].g_iHumanAmmo);
				case 2: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityButtons2");
				case 3: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityCooldown", g_esCache[param1].g_iHumanCooldown);
				case 4: MT_PrintToChat(param1, "%s %t", MT_TAG3, "ShakeDetails");
				case 5: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityDuration2", g_esCache[param1].g_iShakeDuration);
				case 6: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iHumanAbility == 0 ? "AbilityHumanSupport1" : "AbilityHumanSupport2");
			}

			if (bIsValidClient(param1, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
			{
				vShakeMenu(param1, menu.Selection);
			}
		}
		case MenuAction_Display:
		{
			char sMenuTitle[255];
			Panel panel = view_as<Panel>(param2);
			FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "ShakeMenu", param1);
			panel.SetTitle(sMenuTitle);
		}
		case MenuAction_DisplayItem:
		{
			char sMenuOption[255];

			switch (param2)
			{
				case 0:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Status", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 1:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Ammunition", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 2:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Buttons", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 3:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Cooldown", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 4:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Details", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 5:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Duration", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 6:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "HumanSupport", param1);

					return RedrawMenuItem(sMenuOption);
				}
			}
		}
	}

	return 0;
}

public void MT_OnDisplayMenu(Menu menu)
{
	menu.AddItem(MT_MENU_SHAKE, MT_MENU_SHAKE);
}

public void MT_OnMenuItemSelected(int client, const char[] info)
{
	if (StrEqual(info, MT_MENU_SHAKE, false))
	{
		vShakeMenu(client, 0);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (MT_IsCorePluginEnabled() && bIsValidClient(victim, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && damage >= 0.5)
	{
		static char sClassname[32];
		GetEntityClassname(inflictor, sClassname, sizeof(sClassname));
		if (MT_IsTankSupported(attacker) && bIsCloneAllowed(attacker) && (g_esCache[attacker].g_iShakeHitMode == 0 || g_esCache[attacker].g_iShakeHitMode == 1) && bIsHumanSurvivor(victim))
		{
			if ((!MT_HasAdminAccess(attacker) && !bHasAdminAccess(attacker, g_esAbility[g_esPlayer[attacker].g_iTankType].g_iAccessFlags, g_esPlayer[attacker].g_iAccessFlags)) || MT_IsAdminImmune(victim, attacker) || bIsAdminImmune(victim, g_esPlayer[attacker].g_iTankType, g_esAbility[g_esPlayer[attacker].g_iTankType].g_iImmunityFlags, g_esPlayer[victim].g_iImmunityFlags))
			{
				return Plugin_Continue;
			}

			if (StrEqual(sClassname, "weapon_tank_claw") || StrEqual(sClassname, "tank_rock"))
			{
				vShakeHit(victim, attacker, g_esCache[attacker].g_flShakeChance, g_esCache[attacker].g_iShakeHit, MT_MESSAGE_MELEE, MT_ATTACK_CLAW);
			}
		}
		else if (MT_IsTankSupported(victim) && bIsCloneAllowed(victim) && (g_esCache[victim].g_iShakeHitMode == 0 || g_esCache[victim].g_iShakeHitMode == 2) && bIsHumanSurvivor(attacker))
		{
			if ((!MT_HasAdminAccess(victim) && !bHasAdminAccess(victim, g_esAbility[g_esPlayer[victim].g_iTankType].g_iAccessFlags, g_esPlayer[victim].g_iAccessFlags)) || MT_IsAdminImmune(attacker, victim) || bIsAdminImmune(attacker, g_esPlayer[victim].g_iTankType, g_esAbility[g_esPlayer[victim].g_iTankType].g_iImmunityFlags, g_esPlayer[attacker].g_iImmunityFlags))
			{
				return Plugin_Continue;
			}

			if (StrEqual(sClassname, "weapon_melee"))
			{
				vShakeHit(attacker, victim, g_esCache[victim].g_flShakeChance, g_esCache[victim].g_iShakeHit, MT_MESSAGE_MELEE, MT_ATTACK_MELEE);
			}
		}
	}

	return Plugin_Continue;
}

public void MT_OnPluginCheck(ArrayList &list)
{
	char sName[32];
	GetPluginFilename(null, sName, sizeof(sName));
	list.PushString(sName);
}

public void MT_OnAbilityCheck(ArrayList &list, ArrayList &list2, ArrayList &list3, ArrayList &list4)
{
	list.PushString("shakeability");
	list2.PushString("shake ability");
	list3.PushString("shake_ability");
	list4.PushString("shake");
}

public void MT_OnConfigsLoad(int mode)
{
	switch (mode)
	{
		case 1:
		{
			for (int iIndex = MT_GetMinType(); iIndex <= MT_GetMaxType(); iIndex++)
			{
				g_esAbility[iIndex].g_iAccessFlags = 0;
				g_esAbility[iIndex].g_iImmunityFlags = 0;
				g_esAbility[iIndex].g_iHumanAbility = 0;
				g_esAbility[iIndex].g_iHumanAmmo = 5;
				g_esAbility[iIndex].g_iHumanCooldown = 30;
				g_esAbility[iIndex].g_iShakeAbility = 0;
				g_esAbility[iIndex].g_iShakeEffect = 0;
				g_esAbility[iIndex].g_iShakeMessage = 0;
				g_esAbility[iIndex].g_flShakeChance = 33.3;
				g_esAbility[iIndex].g_iShakeDeath = 0;
				g_esAbility[iIndex].g_flShakeDeathChance = 33.3;
				g_esAbility[iIndex].g_flShakeDeathRange = 200.0;
				g_esAbility[iIndex].g_iShakeDuration = 5;
				g_esAbility[iIndex].g_iShakeHit = 0;
				g_esAbility[iIndex].g_iShakeHitMode = 0;
				g_esAbility[iIndex].g_flShakeInterval = 1.0;
				g_esAbility[iIndex].g_flShakeRange = 150.0;
				g_esAbility[iIndex].g_flShakeRangeChance = 15.0;
			}
		}
		case 3:
		{
			for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
			{
				if (bIsValidClient(iPlayer))
				{
					g_esPlayer[iPlayer].g_iAccessFlags = 0;
					g_esPlayer[iPlayer].g_iImmunityFlags = 0;
					g_esPlayer[iPlayer].g_iHumanAbility = 0;
					g_esPlayer[iPlayer].g_iHumanAmmo = 0;
					g_esPlayer[iPlayer].g_iHumanCooldown = 0;
					g_esPlayer[iPlayer].g_iShakeAbility = 0;
					g_esPlayer[iPlayer].g_iShakeEffect = 0;
					g_esPlayer[iPlayer].g_iShakeMessage = 0;
					g_esPlayer[iPlayer].g_flShakeChance = 0.0;
					g_esPlayer[iPlayer].g_iShakeDeath = 0;
					g_esPlayer[iPlayer].g_flShakeDeathChance = 0.0;
					g_esPlayer[iPlayer].g_flShakeDeathRange = 0.0;
					g_esPlayer[iPlayer].g_iShakeDuration = 0;
					g_esPlayer[iPlayer].g_iShakeHit = 0;
					g_esPlayer[iPlayer].g_iShakeHitMode = 0;
					g_esPlayer[iPlayer].g_flShakeInterval = 0.0;
					g_esPlayer[iPlayer].g_flShakeRange = 0.0;
					g_esPlayer[iPlayer].g_flShakeRangeChance = 0.0;
				}
			}
		}
	}
}

public void MT_OnConfigsLoaded(const char[] subsection, const char[] key, const char[] value, int type, int admin, int mode)
{
	if (mode == 3 && bIsValidClient(admin))
	{
		g_esPlayer[admin].g_iHumanAbility = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esPlayer[admin].g_iHumanAbility, value, 0, 2);
		g_esPlayer[admin].g_iHumanAmmo = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "HumanAmmo", "Human Ammo", "Human_Ammo", "hammo", g_esPlayer[admin].g_iHumanAmmo, value, 0, 999999);
		g_esPlayer[admin].g_iHumanCooldown = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "HumanCooldown", "Human Cooldown", "Human_Cooldown", "hcooldown", g_esPlayer[admin].g_iHumanCooldown, value, 0, 999999);
		g_esPlayer[admin].g_iShakeAbility = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esPlayer[admin].g_iShakeAbility, value, 0, 1);
		g_esPlayer[admin].g_iShakeEffect = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esPlayer[admin].g_iShakeEffect, value, 0, 7);
		g_esPlayer[admin].g_iShakeMessage = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esPlayer[admin].g_iShakeMessage, value, 0, 3);
		g_esPlayer[admin].g_flShakeChance = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeChance", "Shake Chance", "Shake_Chance", "chance", g_esPlayer[admin].g_flShakeChance, value, 0.0, 100.0);
		g_esPlayer[admin].g_iShakeDeath = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDeath", "Shake Death", "Shake_Death", "death", g_esPlayer[admin].g_iShakeDeath, value, 0, 1);
		g_esPlayer[admin].g_flShakeDeathChance = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDeathChance", "Shake Death Chance", "Shake_Death_Chance", "deathchance", g_esPlayer[admin].g_flShakeDeathChance, value, 0.0, 100.0);
		g_esPlayer[admin].g_flShakeDeathRange = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDeathRange", "Shake Death Range", "Shake_Death_Range", "deathrange", g_esPlayer[admin].g_flShakeDeathRange, value, 1.0, 999999.0);
		g_esPlayer[admin].g_iShakeDuration = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDuration", "Shake Duration", "Shake_Duration", "duration", g_esPlayer[admin].g_iShakeDuration, value, 1, 999999);
		g_esPlayer[admin].g_iShakeHit = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeHit", "Shake Hit", "Shake_Hit", "hit", g_esPlayer[admin].g_iShakeHit, value, 0, 1);
		g_esPlayer[admin].g_iShakeHitMode = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeHitMode", "Shake Hit Mode", "Shake_Hit_Mode", "hitmode", g_esPlayer[admin].g_iShakeHitMode, value, 0, 2);
		g_esPlayer[admin].g_flShakeInterval = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeInterval", "Shake Interval", "Shake_Interval", "interval", g_esPlayer[admin].g_flShakeInterval, value, 0.1, 999999.0);
		g_esPlayer[admin].g_flShakeRange = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeRange", "Shake Range", "Shake_Range", "range", g_esPlayer[admin].g_flShakeRange, value, 1.0, 999999.0);
		g_esPlayer[admin].g_flShakeRangeChance = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeRangeChance", "Shake Range Chance", "Shake_Range_Chance", "rangechance", g_esPlayer[admin].g_flShakeRangeChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "shakeability", false) || StrEqual(subsection, "shake ability", false) || StrEqual(subsection, "shake_ability", false) || StrEqual(subsection, "shake", false))
		{
			if (StrEqual(key, "AccessFlags", false) || StrEqual(key, "Access Flags", false) || StrEqual(key, "Access_Flags", false) || StrEqual(key, "access", false))
			{
				g_esPlayer[admin].g_iAccessFlags = ReadFlagString(value);
			}
			else if (StrEqual(key, "ImmunityFlags", false) || StrEqual(key, "Immunity Flags", false) || StrEqual(key, "Immunity_Flags", false) || StrEqual(key, "immunity", false))
			{
				g_esPlayer[admin].g_iImmunityFlags = ReadFlagString(value);
			}
		}
	}

	if (mode < 3 && type > 0)
	{
		g_esAbility[type].g_iHumanAbility = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esAbility[type].g_iHumanAbility, value, 0, 2);
		g_esAbility[type].g_iHumanAmmo = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "HumanAmmo", "Human Ammo", "Human_Ammo", "hammo", g_esAbility[type].g_iHumanAmmo, value, 0, 999999);
		g_esAbility[type].g_iHumanCooldown = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "HumanCooldown", "Human Cooldown", "Human_Cooldown", "hcooldown", g_esAbility[type].g_iHumanCooldown, value, 0, 999999);
		g_esAbility[type].g_iShakeAbility = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esAbility[type].g_iShakeAbility, value, 0, 1);
		g_esAbility[type].g_iShakeEffect = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esAbility[type].g_iShakeEffect, value, 0, 7);
		g_esAbility[type].g_iShakeMessage = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esAbility[type].g_iShakeMessage, value, 0, 3);
		g_esAbility[type].g_flShakeChance = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeChance", "Shake Chance", "Shake_Chance", "chance", g_esAbility[type].g_flShakeChance, value, 0.0, 100.0);
		g_esAbility[type].g_iShakeDeath = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDeath", "Shake Death", "Shake_Death", "death", g_esAbility[type].g_iShakeDeath, value, 0, 1);
		g_esAbility[type].g_flShakeDeathChance = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDeathChance", "Shake Death Chance", "Shake_Death_Chance", "deathchance", g_esAbility[type].g_flShakeDeathChance, value, 0.0, 100.0);
		g_esAbility[type].g_flShakeDeathRange = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDeathRange", "Shake Death Range", "Shake_Death_Range", "deathrange", g_esAbility[type].g_flShakeDeathRange, value, 1.0, 999999.0);
		g_esAbility[type].g_iShakeDuration = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeDuration", "Shake Duration", "Shake_Duration", "duration", g_esAbility[type].g_iShakeDuration, value, 1, 999999);
		g_esAbility[type].g_iShakeHit = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeHit", "Shake Hit", "Shake_Hit", "hit", g_esAbility[type].g_iShakeHit, value, 0, 1);
		g_esAbility[type].g_iShakeHitMode = iGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeHitMode", "Shake Hit Mode", "Shake_Hit_Mode", "hitmode", g_esAbility[type].g_iShakeHitMode, value, 0, 2);
		g_esAbility[type].g_flShakeInterval = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeInterval", "Shake Interval", "Shake_Interval", "interval", g_esAbility[type].g_flShakeInterval, value, 0.1, 999999.0);
		g_esAbility[type].g_flShakeRange = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeRange", "Shake Range", "Shake_Range", "range", g_esAbility[type].g_flShakeRange, value, 1.0, 999999.0);
		g_esAbility[type].g_flShakeRangeChance = flGetKeyValue(subsection, "shakeability", "shake ability", "shake_ability", "shake", key, "ShakeRangeChance", "Shake Range Chance", "Shake_Range_Chance", "rangechance", g_esAbility[type].g_flShakeRangeChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "shakeability", false) || StrEqual(subsection, "shake ability", false) || StrEqual(subsection, "shake_ability", false) || StrEqual(subsection, "shake", false))
		{
			if (StrEqual(key, "AccessFlags", false) || StrEqual(key, "Access Flags", false) || StrEqual(key, "Access_Flags", false) || StrEqual(key, "access", false))
			{
				g_esAbility[type].g_iAccessFlags = ReadFlagString(value);
			}
			else if (StrEqual(key, "ImmunityFlags", false) || StrEqual(key, "Immunity Flags", false) || StrEqual(key, "Immunity_Flags", false) || StrEqual(key, "immunity", false))
			{
				g_esAbility[type].g_iImmunityFlags = ReadFlagString(value);
			}
		}
	}
}

public void MT_OnSettingsCached(int tank, bool apply, int type)
{
	bool bHuman = MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT);
	g_esCache[tank].g_flShakeChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShakeChance, g_esAbility[type].g_flShakeChance);
	g_esCache[tank].g_flShakeDeathChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShakeDeathChance, g_esAbility[type].g_flShakeDeathChance);
	g_esCache[tank].g_flShakeDeathRange = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShakeDeathRange, g_esAbility[type].g_flShakeDeathRange);
	g_esCache[tank].g_flShakeInterval = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShakeInterval, g_esAbility[type].g_flShakeInterval);
	g_esCache[tank].g_flShakeRange = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShakeRange, g_esAbility[type].g_flShakeRange);
	g_esCache[tank].g_flShakeRangeChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShakeRangeChance, g_esAbility[type].g_flShakeRangeChance);
	g_esCache[tank].g_iHumanAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAbility, g_esAbility[type].g_iHumanAbility);
	g_esCache[tank].g_iHumanAmmo = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAmmo, g_esAbility[type].g_iHumanAmmo);
	g_esCache[tank].g_iHumanCooldown = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanCooldown, g_esAbility[type].g_iHumanCooldown);
	g_esCache[tank].g_iShakeAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeAbility, g_esAbility[type].g_iShakeAbility);
	g_esCache[tank].g_iShakeDeath = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeDeath, g_esAbility[type].g_iShakeDeath);
	g_esCache[tank].g_iShakeDuration = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeDuration, g_esAbility[type].g_iShakeDuration);
	g_esCache[tank].g_iShakeEffect = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeEffect, g_esAbility[type].g_iShakeEffect);
	g_esCache[tank].g_iShakeHit = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeHit, g_esAbility[type].g_iShakeHit);
	g_esCache[tank].g_iShakeHitMode = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeHitMode, g_esAbility[type].g_iShakeHitMode);
	g_esCache[tank].g_iShakeMessage = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShakeMessage, g_esAbility[type].g_iShakeMessage);
	g_esPlayer[tank].g_iTankType = apply ? type : 0;
}

public void MT_OnEventFired(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(name, "player_death") || StrEqual(name, "player_spawn"))
	{
		int iTankId = event.GetInt("userid"), iTank = GetClientOfUserId(iTankId);
		if (MT_IsTankSupported(iTank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vShakeRange(iTank);
			vRemoveShake(iTank);
		}
	}
}

public void MT_OnAbilityActivated(int tank)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || g_esCache[tank].g_iHumanAbility == 0))
	{
		return;
	}

	if (MT_IsTankSupported(tank) && (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || g_esCache[tank].g_iHumanAbility != 1) && bIsCloneAllowed(tank) && g_esCache[tank].g_iShakeAbility == 1)
	{
		vShakeAbility(tank);
	}
}

public void MT_OnButtonPressed(int tank, int button)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && bIsCloneAllowed(tank))
	{
		if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
		{
			return;
		}

		if (button & MT_SUB_KEY)
		{
			if (g_esCache[tank].g_iShakeAbility == 1 && g_esCache[tank].g_iHumanAbility == 1)
			{
				static int iTime;
				iTime = GetTime();

				switch (g_esPlayer[tank].g_iCooldown == -1 || g_esPlayer[tank].g_iCooldown < iTime)
				{
					case true: vShakeAbility(tank);
					case false: MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeHuman3", g_esPlayer[tank].g_iCooldown - iTime);
				}
			}
		}
	}
}

public void MT_OnChangeType(int tank, bool revert)
{
	vRemoveShake(tank);
}

public void MT_OnPostTankSpawn(int tank)
{
	vShakeRange(tank);
}

static void vRemoveShake(int tank)
{
	for (int iSurvivor = 1; iSurvivor <= MaxClients; iSurvivor++)
	{
		if (bIsHumanSurvivor(iSurvivor, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && g_esPlayer[iSurvivor].g_bAffected && g_esPlayer[iSurvivor].g_iOwner == tank)
		{
			g_esPlayer[iSurvivor].g_bAffected = false;
			g_esPlayer[iSurvivor].g_iOwner = 0;
		}
	}

	vReset3(tank);
}

static void vReset()
{
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (bIsValidClient(iPlayer, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vReset3(iPlayer);

			g_esPlayer[iPlayer].g_iOwner = 0;
		}
	}
}

static void vReset2(int survivor, int tank, int messages)
{
	g_esPlayer[survivor].g_bAffected = false;
	g_esPlayer[survivor].g_iOwner = 0;

	if (g_esCache[tank].g_iShakeMessage & messages)
	{
		MT_PrintToChatAll("%s %t", MT_TAG2, "Shake2", survivor);
	}
}

static void vReset3(int tank)
{
	g_esPlayer[tank].g_bAffected = false;
	g_esPlayer[tank].g_bFailed = false;
	g_esPlayer[tank].g_bNoAmmo = false;
	g_esPlayer[tank].g_iCooldown = -1;
	g_esPlayer[tank].g_iCount = 0;
}

static void vShake(int survivor, float duration = 1.0)
{
	static Handle hTarget;
	hTarget = StartMessageOne("Shake", survivor);

	static BfWrite bfWrite;
	bfWrite = UserMessageToBfWrite(hTarget);
	bfWrite.WriteByte(0);
	bfWrite.WriteFloat(16.0);
	bfWrite.WriteFloat(0.5);
	bfWrite.WriteFloat(duration);

	EndMessage();
}

static void vShakeAbility(int tank)
{
	if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
	{
		return;
	}

	if (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0))
	{
		g_esPlayer[tank].g_bFailed = false;
		g_esPlayer[tank].g_bNoAmmo = false;

		static float flTankPos[3];
		GetClientAbsOrigin(tank, flTankPos);

		static float flSurvivorPos[3], flDistance;
		static int iSurvivorCount;
		iSurvivorCount = 0;
		for (int iSurvivor = 1; iSurvivor <= MaxClients; iSurvivor++)
		{
			if (bIsHumanSurvivor(iSurvivor, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && !MT_IsAdminImmune(iSurvivor, tank) && !bIsAdminImmune(iSurvivor, g_esPlayer[tank].g_iTankType, g_esAbility[g_esPlayer[tank].g_iTankType].g_iImmunityFlags, g_esPlayer[iSurvivor].g_iImmunityFlags))
			{
				GetClientAbsOrigin(iSurvivor, flSurvivorPos);

				flDistance = GetVectorDistance(flTankPos, flSurvivorPos);
				if (flDistance <= g_esCache[tank].g_flShakeRange)
				{
					vShakeHit(iSurvivor, tank, g_esCache[tank].g_flShakeRangeChance, g_esCache[tank].g_iShakeAbility, MT_MESSAGE_RANGE, MT_ATTACK_RANGE);

					iSurvivorCount++;
				}
			}
		}

		if (iSurvivorCount == 0)
		{
			if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
			{
				MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeHuman4");
			}
		}
	}
	else if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
	{
		MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeAmmo");
	}
}

static void vShakeHit(int survivor, int tank, float chance, int enabled, int messages, int flags)
{
	if ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || MT_IsAdminImmune(survivor, tank) || bIsAdminImmune(survivor, g_esPlayer[tank].g_iTankType, g_esAbility[g_esPlayer[tank].g_iTankType].g_iImmunityFlags, g_esPlayer[survivor].g_iImmunityFlags))
	{
		return;
	}

	if (enabled == 1 && bIsSurvivor(survivor))
	{
		if (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0))
		{
			static int iTime;
			iTime = GetTime();
			if (GetRandomFloat(0.1, 100.0) <= chance && !g_esPlayer[survivor].g_bAffected)
			{
				g_esPlayer[survivor].g_bAffected = true;
				g_esPlayer[survivor].g_iOwner = tank;

				if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && (flags & MT_ATTACK_RANGE) && (g_esPlayer[tank].g_iCooldown == -1 || g_esPlayer[tank].g_iCooldown < iTime))
				{
					g_esPlayer[tank].g_iCount++;

					MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeHuman", g_esPlayer[tank].g_iCount, g_esCache[tank].g_iHumanAmmo);

					g_esPlayer[tank].g_iCooldown = (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0) ? (iTime + g_esCache[tank].g_iHumanCooldown) : -1;
					if (g_esPlayer[tank].g_iCooldown != -1 && g_esPlayer[tank].g_iCooldown > iTime)
					{
						MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeHuman5", g_esPlayer[tank].g_iCooldown - iTime);
					}
				}

				DataPack dpShake;
				CreateDataTimer(g_esCache[tank].g_flShakeInterval, tTimerShake, dpShake, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
				dpShake.WriteCell(GetClientUserId(survivor));
				dpShake.WriteCell(GetClientUserId(tank));
				dpShake.WriteCell(g_esPlayer[tank].g_iTankType);
				dpShake.WriteCell(messages);
				dpShake.WriteCell(enabled);
				dpShake.WriteCell(GetTime());

				vEffect(survivor, tank, g_esCache[tank].g_iShakeEffect, flags);
				EmitSoundToClient(survivor, (bIsValidGame() ? SOUND_SMASH2 : SOUND_SMASH1));

				if (g_esCache[tank].g_iShakeMessage & messages)
				{
					static char sTankName[33];
					MT_GetTankName(tank, sTankName);
					MT_PrintToChatAll("%s %t", MT_TAG2, "Shake", sTankName, survivor);
				}
			}
			else if ((flags & MT_ATTACK_RANGE) && (g_esPlayer[tank].g_iCooldown == -1 || g_esPlayer[tank].g_iCooldown < iTime))
			{
				if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && !g_esPlayer[tank].g_bFailed)
				{
					g_esPlayer[tank].g_bFailed = true;

					MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeHuman2");
				}
			}
		}
		else if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && !g_esPlayer[tank].g_bNoAmmo)
		{
			g_esPlayer[tank].g_bNoAmmo = true;

			MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShakeAmmo");
		}
	}
}

static void vShakeRange(int tank)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE) && bIsCloneAllowed(tank) && g_esCache[tank].g_iShakeDeath == 1 && GetRandomFloat(0.1, 100.0) <= g_esCache[tank].g_flShakeDeathChance)
	{
		if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
		{
			return;
		}

		static float flTankPos[3];
		GetClientAbsOrigin(tank, flTankPos);

		static float flSurvivorPos[3], flDistance;
		for (int iSurvivor = 1; iSurvivor <= MaxClients; iSurvivor++)
		{
			if (bIsSurvivor(iSurvivor, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && !MT_IsAdminImmune(iSurvivor, tank) && !bIsAdminImmune(iSurvivor, g_esPlayer[tank].g_iTankType, g_esAbility[g_esPlayer[tank].g_iTankType].g_iImmunityFlags, g_esPlayer[iSurvivor].g_iImmunityFlags))
			{
				GetClientAbsOrigin(iSurvivor, flSurvivorPos);

				flDistance = GetVectorDistance(flTankPos, flSurvivorPos);
				if (flDistance <= g_esCache[tank].g_flShakeDeathRange)
				{
					vShake(tank, 2.0);
				}
			}
		}
	}
}

public Action tTimerShake(Handle timer, DataPack pack)
{
	pack.Reset();

	static int iSurvivor;
	iSurvivor = GetClientOfUserId(pack.ReadCell());
	if (!MT_IsCorePluginEnabled() || !bIsHumanSurvivor(iSurvivor))
	{
		g_esPlayer[iSurvivor].g_bAffected = false;
		g_esPlayer[iSurvivor].g_iOwner = 0;

		return Plugin_Stop;
	}

	static int iTank, iType, iMessage;
	iTank = GetClientOfUserId(pack.ReadCell());
	iType = pack.ReadCell();
	iMessage = pack.ReadCell();
	if (!MT_IsTankSupported(iTank) || (!MT_HasAdminAccess(iTank) && !bHasAdminAccess(iTank, g_esAbility[g_esPlayer[iTank].g_iTankType].g_iAccessFlags, g_esPlayer[iTank].g_iAccessFlags)) || !MT_IsTypeEnabled(g_esPlayer[iTank].g_iTankType) || !bIsCloneAllowed(iTank) || iType != g_esPlayer[iTank].g_iTankType || MT_IsAdminImmune(iSurvivor, iTank) || bIsAdminImmune(iSurvivor, g_esPlayer[iTank].g_iTankType, g_esAbility[g_esPlayer[iTank].g_iTankType].g_iImmunityFlags, g_esPlayer[iSurvivor].g_iImmunityFlags) || !g_esPlayer[iSurvivor].g_bAffected)
	{
		vReset2(iSurvivor, iTank, iMessage);

		return Plugin_Stop;
	}

	static int iShakeEnabled, iTime;
	iShakeEnabled = pack.ReadCell();
	iTime = pack.ReadCell();
	if (iShakeEnabled == 0 || (iTime + g_esCache[iTank].g_iShakeDuration) < GetTime())
	{
		vReset2(iSurvivor, iTank, iMessage);

		return Plugin_Stop;
	}

	vShake(iSurvivor);

	return Plugin_Continue;
}