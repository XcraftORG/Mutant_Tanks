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
	name = "[MT] Kamikaze Ability",
	author = MT_AUTHOR,
	description = "The Mutant Tank kills itself along with a survivor victim.",
	version = MT_VERSION,
	url = MT_URL
};

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!bIsValidGame(false) && !bIsValidGame())
	{
		strcopy(error, err_max, "\"[MT] Kamikaze Ability\" only supports Left 4 Dead 1 & 2.");

		return APLRes_SilentFailure;
	}

	g_bLateLoad = late;

	return APLRes_Success;
}

#define PARTICLE_BLOOD "boomer_explode_D"

#define SOUND_GROWL2 "player/tank/voice/growl/tank_climb_01.wav" // Only exists on L4D2
#define SOUND_GROWL1 "player/tank/voice/growl/hulk_growl_1.wav" // Only exists on L4D1
#define SOUND_SMASH2 "player/charger/hit/charger_smash_02.wav" // Only exists on L4D2
#define SOUND_SMASH1 "player/tank/hit/hulk_punch_1.wav"

#define MT_MENU_KAMIKAZE "Kamikaze Ability"

enum struct esPlayer
{
	bool g_bFailed;

	float g_flKamikazeChance;
	float g_flKamikazeRange;
	float g_flKamikazeRangeChance;

	int g_iAccessFlags;
	int g_iHumanAbility;
	int g_iImmunityFlags;
	int g_iKamikazeAbility;
	int g_iKamikazeEffect;
	int g_iKamikazeHit;
	int g_iKamikazeHitMode;
	int g_iKamikazeMessage;
	int g_iTankType;
}

esPlayer g_esPlayer[MAXPLAYERS + 1];

enum struct esAbility
{
	float g_flKamikazeChance;
	float g_flKamikazeRange;
	float g_flKamikazeRangeChance;

	int g_iAccessFlags;
	int g_iHumanAbility;
	int g_iImmunityFlags;
	int g_iKamikazeAbility;
	int g_iKamikazeEffect;
	int g_iKamikazeHit;
	int g_iKamikazeHitMode;
	int g_iKamikazeMessage;
}

esAbility g_esAbility[MT_MAXTYPES + 1];

enum struct esCache
{
	float g_flKamikazeChance;
	float g_flKamikazeRange;
	float g_flKamikazeRangeChance;

	int g_iHumanAbility;
	int g_iKamikazeAbility;
	int g_iKamikazeEffect;
	int g_iKamikazeHit;
	int g_iKamikazeHitMode;
	int g_iKamikazeMessage;
}

esCache g_esCache[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mutant_tanks.phrases");

	RegConsoleCmd("sm_mt_kamikaze", cmdKamikazeInfo, "View information about the Kamikaze ability.");

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
	iPrecacheParticle(PARTICLE_BLOOD);

	if (bIsValidGame())
	{
		PrecacheSound(SOUND_GROWL2, true);
		PrecacheSound(SOUND_SMASH2, true);
	}
	else
	{
		PrecacheSound(SOUND_GROWL1, true);
		PrecacheSound(SOUND_SMASH1, true);
	}

	vReset();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	vRemoveKamikaze(client);
}

public void OnClientDisconnect_Post(int client)
{
	vRemoveKamikaze(client);
}

public void OnMapEnd()
{
	vReset();
}

public Action cmdKamikazeInfo(int client, int args)
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
		case false: vKamikazeMenu(client, 0);
	}

	return Plugin_Handled;
}

static void vKamikazeMenu(int client, int item)
{
	Menu mAbilityMenu = new Menu(iKamikazeMenuHandler, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	mAbilityMenu.SetTitle("Kamikaze Ability Information");
	mAbilityMenu.AddItem("Status", "Status");
	mAbilityMenu.AddItem("Buttons", "Buttons");
	mAbilityMenu.AddItem("Details", "Details");
	mAbilityMenu.AddItem("Human Support", "Human Support");
	mAbilityMenu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int iKamikazeMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End: delete menu;
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iKamikazeAbility == 0 ? "AbilityStatus1" : "AbilityStatus2");
				case 1: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityButtons2");
				case 2: MT_PrintToChat(param1, "%s %t", MT_TAG3, "KamikazeDetails");
				case 3: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iHumanAbility == 0 ? "AbilityHumanSupport1" : "AbilityHumanSupport2");
			}

			if (bIsValidClient(param1, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
			{
				vKamikazeMenu(param1, menu.Selection);
			}
		}
		case MenuAction_Display:
		{
			char sMenuTitle[255];
			Panel panel = view_as<Panel>(param2);
			FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "KamikazeMenu", param1);
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
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Buttons", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 2:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Details", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 3:
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
	menu.AddItem(MT_MENU_KAMIKAZE, MT_MENU_KAMIKAZE);
}

public void MT_OnMenuItemSelected(int client, const char[] info)
{
	if (StrEqual(info, MT_MENU_KAMIKAZE, false))
	{
		vKamikazeMenu(client, 0);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (MT_IsCorePluginEnabled() && bIsValidClient(victim, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && damage >= 0.5)
	{
		static char sClassname[32];
		GetEntityClassname(inflictor, sClassname, sizeof(sClassname));
		if (MT_IsTankSupported(attacker) && bIsCloneAllowed(attacker) && (g_esCache[attacker].g_iKamikazeHitMode == 0 || g_esCache[attacker].g_iKamikazeHitMode == 1) && bIsSurvivor(victim))
		{
			if ((!MT_HasAdminAccess(attacker) && !bHasAdminAccess(attacker, g_esAbility[g_esPlayer[attacker].g_iTankType].g_iAccessFlags, g_esPlayer[attacker].g_iAccessFlags)) || MT_IsAdminImmune(victim, attacker) || bIsAdminImmune(victim, g_esPlayer[attacker].g_iTankType, g_esAbility[g_esPlayer[attacker].g_iTankType].g_iImmunityFlags, g_esPlayer[victim].g_iImmunityFlags))
			{
				return Plugin_Continue;
			}

			if (StrEqual(sClassname, "weapon_tank_claw") || StrEqual(sClassname, "tank_rock"))
			{
				vKamikazeHit(victim, attacker, g_esCache[attacker].g_flKamikazeChance, g_esCache[attacker].g_iKamikazeHit, MT_MESSAGE_MELEE, MT_ATTACK_CLAW);
			}
		}
		else if (MT_IsTankSupported(victim) && bIsCloneAllowed(victim) && (g_esCache[victim].g_iKamikazeHitMode == 0 || g_esCache[victim].g_iKamikazeHitMode == 2) && bIsSurvivor(attacker))
		{
			if ((!MT_HasAdminAccess(victim) && !bHasAdminAccess(victim, g_esAbility[g_esPlayer[victim].g_iTankType].g_iAccessFlags, g_esPlayer[victim].g_iAccessFlags)) || MT_IsAdminImmune(attacker, victim) || bIsAdminImmune(attacker, g_esPlayer[victim].g_iTankType, g_esAbility[g_esPlayer[victim].g_iTankType].g_iImmunityFlags, g_esPlayer[attacker].g_iImmunityFlags))
			{
				return Plugin_Continue;
			}

			if (StrEqual(sClassname, "weapon_melee"))
			{
				vKamikazeHit(attacker, victim, g_esCache[victim].g_flKamikazeChance, g_esCache[victim].g_iKamikazeHit, MT_MESSAGE_MELEE, MT_ATTACK_MELEE);
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
	list.PushString("kamikazeability");
	list2.PushString("kamikaze ability");
	list3.PushString("kamikaze_ability");
	list4.PushString("kamikaze");
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
				g_esAbility[iIndex].g_iKamikazeAbility = 0;
				g_esAbility[iIndex].g_iKamikazeEffect = 0;
				g_esAbility[iIndex].g_iKamikazeMessage = 0;
				g_esAbility[iIndex].g_flKamikazeChance = 33.3;
				g_esAbility[iIndex].g_iKamikazeHit = 0;
				g_esAbility[iIndex].g_iKamikazeHitMode = 0;
				g_esAbility[iIndex].g_flKamikazeRange = 150.0;
				g_esAbility[iIndex].g_flKamikazeRangeChance = 15.0;
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
					g_esPlayer[iPlayer].g_iKamikazeAbility = 0;
					g_esPlayer[iPlayer].g_iKamikazeEffect = 0;
					g_esPlayer[iPlayer].g_iKamikazeMessage = 0;
					g_esPlayer[iPlayer].g_flKamikazeChance = 0.0;
					g_esPlayer[iPlayer].g_iKamikazeHit = 0;
					g_esPlayer[iPlayer].g_iKamikazeHitMode = 0;
					g_esPlayer[iPlayer].g_flKamikazeRange = 0.0;
					g_esPlayer[iPlayer].g_flKamikazeRangeChance = 0.0;
				}
			}
		}
	}
}

public void MT_OnConfigsLoaded(const char[] subsection, const char[] key, const char[] value, int type, int admin, int mode)
{
	if (mode == 3 && bIsValidClient(admin))
	{
		g_esPlayer[admin].g_iHumanAbility = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esPlayer[admin].g_iHumanAbility, value, 0, 2);
		g_esPlayer[admin].g_iKamikazeAbility = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esPlayer[admin].g_iKamikazeAbility, value, 0, 1);
		g_esPlayer[admin].g_iKamikazeEffect = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esPlayer[admin].g_iKamikazeEffect, value, 0, 7);
		g_esPlayer[admin].g_iKamikazeMessage = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esPlayer[admin].g_iKamikazeMessage, value, 0, 3);
		g_esPlayer[admin].g_flKamikazeChance = flGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeChance", "Kamikaze Chance", "Kamikaze_Chance", "chance", g_esPlayer[admin].g_flKamikazeChance, value, 0.0, 100.0);
		g_esPlayer[admin].g_iKamikazeHit = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeHit", "Kamikaze Hit", "Kamikaze_Hit", "hit", g_esPlayer[admin].g_iKamikazeHit, value, 0, 1);
		g_esPlayer[admin].g_iKamikazeHitMode = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeHitMode", "Kamikaze Hit Mode", "Kamikaze_Hit_Mode", "hitmode", g_esPlayer[admin].g_iKamikazeHitMode, value, 0, 2);
		g_esPlayer[admin].g_flKamikazeRange = flGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeRange", "Kamikaze Range", "Kamikaze_Range", "range", g_esPlayer[admin].g_flKamikazeRange, value, 1.0, 999999.0);
		g_esPlayer[admin].g_flKamikazeRangeChance = flGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeRangeChance", "Kamikaze Range Chance", "Kamikaze_Range_Chance", "rangechance", g_esPlayer[admin].g_flKamikazeRangeChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "kamikazeability", false) || StrEqual(subsection, "kamikaze ability", false) || StrEqual(subsection, "kamikaze_ability", false) || StrEqual(subsection, "kamikaze", false))
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
		g_esAbility[type].g_iHumanAbility = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esAbility[type].g_iHumanAbility, value, 0, 2);
		g_esAbility[type].g_iKamikazeAbility = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esAbility[type].g_iKamikazeAbility, value, 0, 1);
		g_esAbility[type].g_iKamikazeEffect = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esAbility[type].g_iKamikazeEffect, value, 0, 7);
		g_esAbility[type].g_iKamikazeMessage = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esAbility[type].g_iKamikazeMessage, value, 0, 3);
		g_esAbility[type].g_flKamikazeChance = flGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeChance", "Kamikaze Chance", "Kamikaze_Chance", "chance", g_esAbility[type].g_flKamikazeChance, value, 0.0, 100.0);
		g_esAbility[type].g_iKamikazeHit = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeHit", "Kamikaze Hit", "Kamikaze_Hit", "hit", g_esAbility[type].g_iKamikazeHit, value, 0, 1);
		g_esAbility[type].g_iKamikazeHitMode = iGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeHitMode", "Kamikaze Hit Mode", "Kamikaze_Hit_Mode", "hitmode", g_esAbility[type].g_iKamikazeHitMode, value, 0, 2);
		g_esAbility[type].g_flKamikazeRange = flGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeRange", "Kamikaze Range", "Kamikaze_Range", "range", g_esAbility[type].g_flKamikazeRange, value, 1.0, 999999.0);
		g_esAbility[type].g_flKamikazeRangeChance = flGetKeyValue(subsection, "kamikazeability", "kamikaze ability", "kamikaze_ability", "kamikaze", key, "KamikazeRangeChance", "Kamikaze Range Chance", "Kamikaze_Range_Chance", "rangechance", g_esAbility[type].g_flKamikazeRangeChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "kamikazeability", false) || StrEqual(subsection, "kamikaze ability", false) || StrEqual(subsection, "kamikaze_ability", false) || StrEqual(subsection, "kamikaze", false))
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
	g_esCache[tank].g_flKamikazeChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flKamikazeChance, g_esAbility[type].g_flKamikazeChance);
	g_esCache[tank].g_flKamikazeRange = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flKamikazeRange, g_esAbility[type].g_flKamikazeRange);
	g_esCache[tank].g_flKamikazeRangeChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flKamikazeRangeChance, g_esAbility[type].g_flKamikazeRangeChance);
	g_esCache[tank].g_iHumanAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAbility, g_esAbility[type].g_iHumanAbility);
	g_esCache[tank].g_iKamikazeAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iKamikazeAbility, g_esAbility[type].g_iKamikazeAbility);
	g_esCache[tank].g_iKamikazeEffect = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iKamikazeEffect, g_esAbility[type].g_iKamikazeEffect);
	g_esCache[tank].g_iKamikazeHit = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iKamikazeHit, g_esAbility[type].g_iKamikazeHit);
	g_esCache[tank].g_iKamikazeHitMode = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iKamikazeHitMode, g_esAbility[type].g_iKamikazeHitMode);
	g_esCache[tank].g_iKamikazeMessage = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iKamikazeMessage, g_esAbility[type].g_iKamikazeMessage);
	g_esPlayer[tank].g_iTankType = apply ? type : 0;
}

public void MT_OnEventFired(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(name, "player_death") || StrEqual(name, "player_spawn"))
	{
		int iTankId = event.GetInt("userid"), iTank = GetClientOfUserId(iTankId);
		if (MT_IsTankSupported(iTank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vRemoveKamikaze(iTank);
		}
	}
}

public void MT_OnAbilityActivated(int tank)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || g_esCache[tank].g_iHumanAbility == 0))
	{
		return;
	}

	if (MT_IsTankSupported(tank) && (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || g_esCache[tank].g_iHumanAbility != 1) && bIsCloneAllowed(tank) && g_esCache[tank].g_iKamikazeAbility == 1)
	{
		vKamikazeAbility(tank);
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
			if (g_esCache[tank].g_iKamikazeAbility == 1 && g_esCache[tank].g_iHumanAbility == 1)
			{
				vKamikazeAbility(tank);
			}
		}
	}
}

public void MT_OnChangeType(int tank, bool revert)
{
	vRemoveKamikaze(tank);
}

public void MT_OnPostTankSpawn(int tank)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE) && bIsCloneAllowed(tank) && g_esCache[tank].g_iKamikazeAbility == 1)
	{
		if (MT_HasAdminAccess(tank) || bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
		{
			vKamikaze(tank, tank);
		}
	}
}

static void vKamikaze(int survivor, int tank)
{
	if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
	{
		return;
	}

	if (bIsValidGame())
	{
		EmitSoundToAll(SOUND_SMASH2, survivor);
		EmitSoundToAll(SOUND_GROWL2, tank);
	}
	else
	{
		EmitSoundToAll(SOUND_SMASH1, survivor);
		EmitSoundToAll(SOUND_GROWL1, tank);
	}

	vAttachParticle(survivor, PARTICLE_BLOOD, 0.1, 0.0);
}

static void vKamikazeAbility(int tank)
{
	if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
	{
		return;
	}

	g_esPlayer[tank].g_bFailed = false;

	static float flTankPos[3];
	GetClientAbsOrigin(tank, flTankPos);

	static float flSurvivorPos[3], flDistance;
	static int iSurvivorCount;
	iSurvivorCount = 0;
	for (int iSurvivor = 1; iSurvivor <= MaxClients; iSurvivor++)
	{
		if (bIsSurvivor(iSurvivor, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && !MT_IsAdminImmune(iSurvivor, tank) && !bIsAdminImmune(iSurvivor, g_esPlayer[tank].g_iTankType, g_esAbility[g_esPlayer[tank].g_iTankType].g_iImmunityFlags, g_esPlayer[iSurvivor].g_iImmunityFlags))
		{
			GetClientAbsOrigin(iSurvivor, flSurvivorPos);

			flDistance = GetVectorDistance(flTankPos, flSurvivorPos);
			if (flDistance <= g_esCache[tank].g_flKamikazeRange)
			{
				vKamikazeHit(iSurvivor, tank, g_esCache[tank].g_flKamikazeRangeChance, g_esCache[tank].g_iKamikazeAbility, MT_MESSAGE_RANGE, MT_ATTACK_RANGE);

				iSurvivorCount++;
			}
		}
	}

	if (iSurvivorCount == 0)
	{
		if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
		{
			MT_PrintToChat(tank, "%s %t", MT_TAG3, "KamikazeHuman3");
		}
	}
}

static void vKamikazeHit(int survivor, int tank, float chance, int enabled, int messages, int flags)
{
	if ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || MT_IsAdminImmune(survivor, tank) || bIsAdminImmune(survivor, g_esPlayer[tank].g_iTankType, g_esAbility[g_esPlayer[tank].g_iTankType].g_iImmunityFlags, g_esPlayer[survivor].g_iImmunityFlags))
	{
		return;
	}

	if (enabled == 1 && bIsSurvivor(survivor))
	{
		if (GetRandomFloat(0.1, 100.0) <= chance)
		{
			if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && (flags & MT_ATTACK_RANGE))
			{
				MT_PrintToChat(tank, "%s %t", MT_TAG3, "KamikazeHuman");
			}

			EmitSoundToAll((bIsValidGame()) ? SOUND_SMASH2 : SOUND_SMASH1, survivor);
			vAttachParticle(survivor, PARTICLE_BLOOD, 0.1, 0.0);
			ForcePlayerSuicide(survivor);

			EmitSoundToAll((bIsValidGame()) ? SOUND_GROWL2 : SOUND_GROWL1, survivor);
			vAttachParticle(tank, PARTICLE_BLOOD, 0.1, 0.0);
			ForcePlayerSuicide(tank);

			vEffect(survivor, tank, g_esCache[tank].g_iKamikazeEffect, flags);

			if (g_esCache[tank].g_iKamikazeMessage & messages)
			{
				static char sTankName[33];
				MT_GetTankName(tank, sTankName);
				MT_PrintToChatAll("%s %t", MT_TAG2, "Kamikaze", sTankName, survivor);
			}
		}
		else if ((flags & MT_ATTACK_RANGE))
		{
			if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && !g_esPlayer[tank].g_bFailed)
			{
				g_esPlayer[tank].g_bFailed = true;

				MT_PrintToChat(tank, "%s %t", MT_TAG3, "KamikazeHuman2");
			}
		}
	}
}

static void vRemoveKamikaze(int tank)
{
	g_esPlayer[tank].g_bFailed = false;
}

static void vReset()
{
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (bIsValidClient(iPlayer, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vRemoveKamikaze(iPlayer);
		}
	}
}