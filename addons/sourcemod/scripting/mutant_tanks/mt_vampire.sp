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
	name = "[MT] Vampire Ability",
	author = MT_AUTHOR,
	description = "The Mutant Tank gains health from hurting survivors.",
	version = MT_VERSION,
	url = MT_URL
};

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!bIsValidGame(false) && !bIsValidGame())
	{
		strcopy(error, err_max, "\"[MT] Vampire Ability\" only supports Left 4 Dead 1 & 2.");

		return APLRes_SilentFailure;
	}

	g_bLateLoad = late;

	return APLRes_Success;
}

#define MT_MENU_VAMPIRE "Vampire Ability"

enum struct esPlayer
{
	float g_flVampireChance;

	int g_iAccessFlags;
	int g_iHumanAbility;
	int g_iImmunityFlags;
	int g_iTankType;
	int g_iVampireAbility;
	int g_iVampireEffect;
	int g_iVampireMessage;
}

esPlayer g_esPlayer[MAXPLAYERS + 1];

enum struct esAbility
{
	float g_flVampireChance;

	int g_iAccessFlags;
	int g_iHumanAbility;
	int g_iImmunityFlags;
	int g_iVampireAbility;
	int g_iVampireEffect;
	int g_iVampireMessage;
}

esAbility g_esAbility[MT_MAXTYPES + 1];

enum struct esCache
{
	float g_flVampireChance;

	int g_iHumanAbility;
	int g_iVampireAbility;
	int g_iVampireEffect;
	int g_iVampireMessage;
}

esCache g_esCache[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mutant_tanks.phrases");

	RegConsoleCmd("sm_mt_vampire", cmdVampireInfo, "View information about the Vampire ability.");

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

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action cmdVampireInfo(int client, int args)
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
		case false: vVampireMenu(client, 0);
	}

	return Plugin_Handled;
}

static void vVampireMenu(int client, int item)
{
	Menu mAbilityMenu = new Menu(iVampireMenuHandler, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	mAbilityMenu.SetTitle("Vampire Ability Information");
	mAbilityMenu.AddItem("Status", "Status");
	mAbilityMenu.AddItem("Details", "Details");
	mAbilityMenu.AddItem("Human Support", "Human Support");
	mAbilityMenu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int iVampireMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End: delete menu;
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iVampireAbility == 0 ? "AbilityStatus1" : "AbilityStatus2");
				case 1: MT_PrintToChat(param1, "%s %t", MT_TAG3, "VampireDetails");
				case 2: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iHumanAbility == 0 ? "AbilityHumanSupport1" : "AbilityHumanSupport2");
			}

			if (bIsValidClient(param1, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
			{
				vVampireMenu(param1, menu.Selection);
			}
		}
		case MenuAction_Display:
		{
			char sMenuTitle[255];
			Panel panel = view_as<Panel>(param2);
			FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "VampireMenu", param1);
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
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Details", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 2:
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
	menu.AddItem(MT_MENU_VAMPIRE, MT_MENU_VAMPIRE);
}

public void MT_OnMenuItemSelected(int client, const char[] info)
{
	if (StrEqual(info, MT_MENU_VAMPIRE, false))
	{
		vVampireMenu(client, 0);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (MT_IsCorePluginEnabled() && bIsValidClient(victim, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && damage >= 0.5)
	{
		static char sClassname[32];
		GetEntityClassname(inflictor, sClassname, sizeof(sClassname));
		if (StrEqual(sClassname, "weapon_tank_claw") || StrEqual(sClassname, "tank_rock"))
		{
			if (MT_IsTankSupported(attacker) && bIsCloneAllowed(attacker) && g_esCache[attacker].g_iVampireAbility == 1 && GetRandomFloat(0.1, 100.0) <= g_esCache[attacker].g_flVampireChance && bIsSurvivor(victim))
			{
				if ((!MT_HasAdminAccess(victim) && !bHasAdminAccess(victim, g_esAbility[g_esPlayer[victim].g_iTankType].g_iAccessFlags, g_esPlayer[victim].g_iAccessFlags)) || MT_IsAdminImmune(attacker, victim) || bIsAdminImmune(attacker, g_esPlayer[victim].g_iTankType, g_esAbility[g_esPlayer[victim].g_iTankType].g_iImmunityFlags, g_esPlayer[attacker].g_iImmunityFlags))
				{
					return Plugin_Continue;
				}

				if (!MT_IsTankSupported(attacker, MT_CHECK_FAKECLIENT) || g_esCache[attacker].g_iHumanAbility == 1)
				{
					static int iDamage, iHealth, iNewHealth, iFinalHealth;
					iDamage = RoundToNearest(damage);
					iHealth = GetClientHealth(attacker);
					iNewHealth = iHealth + iDamage;
					iFinalHealth = (iNewHealth > MT_MAXHEALTH) ? MT_MAXHEALTH : iNewHealth;
					//SetEntityHealth(attacker, iFinalHealth);
					SetEntProp(attacker, Prop_Data, "m_iHealth", iFinalHealth);

					vEffect(victim, attacker, g_esCache[attacker].g_iVampireEffect, 1);

					if (g_esCache[attacker].g_iVampireMessage == 1)
					{
						static char sTankName[33];
						MT_GetTankName(attacker, sTankName);
						MT_PrintToChatAll("%s %t", MT_TAG2, "Vampire", sTankName, victim);
					}
				}
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
	list.PushString("vampireability");
	list2.PushString("vampire ability");
	list3.PushString("vampire_ability");
	list4.PushString("vampire");
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
				g_esAbility[iIndex].g_iVampireAbility = 0;
				g_esAbility[iIndex].g_iVampireEffect = 0;
				g_esAbility[iIndex].g_iVampireMessage = 0;
				g_esAbility[iIndex].g_flVampireChance = 33.3;
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
					g_esPlayer[iPlayer].g_iVampireAbility = 0;
					g_esPlayer[iPlayer].g_iVampireEffect = 0;
					g_esPlayer[iPlayer].g_iVampireMessage = 0;
					g_esPlayer[iPlayer].g_flVampireChance = 0.0;
				}
			}
		}
	}
}

public void MT_OnConfigsLoaded(const char[] subsection, const char[] key, const char[] value, int type, int admin, int mode)
{
	if (mode == 3 && bIsValidClient(admin))
	{
		g_esPlayer[admin].g_iHumanAbility = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esPlayer[admin].g_iHumanAbility, value, 0, 1);
		g_esPlayer[admin].g_iVampireAbility = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esPlayer[admin].g_iVampireAbility, value, 0, 1);
		g_esPlayer[admin].g_iVampireEffect = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esPlayer[admin].g_iVampireEffect, value, 0, 1);
		g_esPlayer[admin].g_iVampireMessage = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esPlayer[admin].g_iVampireMessage, value, 0, 1);
		g_esPlayer[admin].g_flVampireChance = flGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "VampireChance", "Vampire Chance", "Vampire_Chance", "chance", g_esPlayer[admin].g_flVampireChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "vampireability", false) || StrEqual(subsection, "vampire ability", false) || StrEqual(subsection, "vampire_ability", false) || StrEqual(subsection, "vampire", false))
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
		g_esAbility[type].g_iHumanAbility = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esAbility[type].g_iHumanAbility, value, 0, 1);
		g_esAbility[type].g_iVampireAbility = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esAbility[type].g_iVampireAbility, value, 0, 1);
		g_esAbility[type].g_iVampireEffect = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esAbility[type].g_iVampireEffect, value, 0, 1);
		g_esAbility[type].g_iVampireMessage = iGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esAbility[type].g_iVampireMessage, value, 0, 1);
		g_esAbility[type].g_flVampireChance = flGetKeyValue(subsection, "vampireability", "vampire ability", "vampire_ability", "vampire", key, "VampireChance", "Vampire Chance", "Vampire_Chance", "chance", g_esAbility[type].g_flVampireChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "vampireability", false) || StrEqual(subsection, "vampire ability", false) || StrEqual(subsection, "vampire_ability", false) || StrEqual(subsection, "vampire", false))
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
	g_esCache[tank].g_flVampireChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flVampireChance, g_esAbility[type].g_flVampireChance);
	g_esCache[tank].g_iHumanAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAbility, g_esAbility[type].g_iHumanAbility);
	g_esCache[tank].g_iVampireAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iVampireAbility, g_esAbility[type].g_iVampireAbility);
	g_esCache[tank].g_iVampireEffect = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iVampireEffect, g_esAbility[type].g_iVampireEffect);
	g_esCache[tank].g_iVampireMessage = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iVampireMessage, g_esAbility[type].g_iVampireMessage);
	g_esPlayer[tank].g_iTankType = apply ? type : 0;
}