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
	name = "[MT] Electric Ability",
	author = MT_AUTHOR,
	description = "The Mutant Tank electrocutes survivors.",
	version = MT_VERSION,
	url = MT_URL
};

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!bIsValidGame(false) && !bIsValidGame())
	{
		strcopy(error, err_max, "\"[MT] Electric Ability\" only supports Left 4 Dead 1 & 2.");

		return APLRes_SilentFailure;
	}

	g_bLateLoad = late;

	return APLRes_Success;
}

#define PARTICLE_ELECTRICITY "electrical_arc_01"
#define PARTICLE_ELECTRICITY2 "electrical_arc_01_parent"
#define PARTICLE_ELECTRICITY3 "st_elmos_fire"
#define PARTICLE_ELECTRICITY4 "storm_lightning_02"
#define PARTICLE_ELECTRICITY5 "storm_lightning_01"
#define PARTICLE_ELECTRICITY6 "impact_ricochet_sparks"
#define PARTICLE_ELECTRICITY7 "railroad_wheel_sparks"

#define MT_MENU_ELECTRIC "Electric Ability"

char g_sZapSounds[8][25] = { "ambient/energy/zap1.wav", "ambient/energy/zap2.wav", "ambient/energy/zap3.wav", "ambient/energy/zap5.wav", "ambient/energy/zap6.wav", "ambient/energy/zap7.wav", "ambient/energy/zap8.wav", "ambient/energy/zap9.wav" };

enum struct esPlayer
{
	bool g_bAffected;
	bool g_bFailed;
	bool g_bNoAmmo;

	float g_flElectricChance;
	float g_flElectricDamage;
	float g_flElectricInterval;
	float g_flElectricRange;
	float g_flElectricRangeChance;

	int g_iAccessFlags;
	int g_iCooldown;
	int g_iCount;
	int g_iElectricAbility;
	int g_iElectricDuration;
	int g_iElectricEffect;
	int g_iElectricHit;
	int g_iElectricHitMode;
	int g_iElectricMessage;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iImmunityFlags;
	int g_iOwner;
	int g_iTankType;
}

esPlayer g_esPlayer[MAXPLAYERS + 1];

enum struct esAbility
{
	float g_flElectricChance;
	float g_flElectricDamage;
	float g_flElectricInterval;
	float g_flElectricRange;
	float g_flElectricRangeChance;

	int g_iAccessFlags;
	int g_iElectricAbility;
	int g_iElectricDuration;
	int g_iElectricEffect;
	int g_iElectricHit;
	int g_iElectricHitMode;
	int g_iElectricMessage;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iImmunityFlags;
}

esAbility g_esAbility[MT_MAXTYPES + 1];

enum struct esCache
{
	float g_flElectricChance;
	float g_flElectricDamage;
	float g_flElectricInterval;
	float g_flElectricRange;
	float g_flElectricRangeChance;

	int g_iElectricAbility;
	int g_iElectricDuration;
	int g_iElectricEffect;
	int g_iElectricHit;
	int g_iElectricHitMode;
	int g_iElectricMessage;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
}

esCache g_esCache[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mutant_tanks.phrases");

	RegConsoleCmd("sm_mt_electric", cmdElectricInfo, "View information about the Electric ability.");

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
	iPrecacheParticle(PARTICLE_ELECTRICITY2);
	iPrecacheParticle(PARTICLE_ELECTRICITY3);

	switch (bIsValidGame())
	{
		case true:
		{
			iPrecacheParticle(PARTICLE_ELECTRICITY4);
			iPrecacheParticle(PARTICLE_ELECTRICITY5);
		}
		case false:
		{
			iPrecacheParticle(PARTICLE_ELECTRICITY6);
			iPrecacheParticle(PARTICLE_ELECTRICITY7);
		}
	}

	for (int iPos = 0; iPos < sizeof(g_sZapSounds); iPos++)
	{
		PrecacheSound(g_sZapSounds[iPos], true);
	}

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

public Action cmdElectricInfo(int client, int args)
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
		case false: vElectricMenu(client, 0);
	}

	return Plugin_Handled;
}

static void vElectricMenu(int client, int item)
{
	Menu mAbilityMenu = new Menu(iElectricMenuHandler, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	mAbilityMenu.SetTitle("Electric Ability Information");
	mAbilityMenu.AddItem("Status", "Status");
	mAbilityMenu.AddItem("Ammunition", "Ammunition");
	mAbilityMenu.AddItem("Buttons", "Buttons");
	mAbilityMenu.AddItem("Cooldown", "Cooldown");
	mAbilityMenu.AddItem("Details", "Details");
	mAbilityMenu.AddItem("Duration", "Duration");
	mAbilityMenu.AddItem("Human Support", "Human Support");
	mAbilityMenu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int iElectricMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End: delete menu;
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iElectricAbility == 0 ? "AbilityStatus1" : "AbilityStatus2");
				case 1: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityAmmo", g_esCache[param1].g_iHumanAmmo - g_esPlayer[param1].g_iCount, g_esCache[param1].g_iHumanAmmo);
				case 2: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityButtons2");
				case 3: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityCooldown", g_esCache[param1].g_iHumanCooldown);
				case 4: MT_PrintToChat(param1, "%s %t", MT_TAG3, "ElectricDetails");
				case 5: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityDuration2", g_esCache[param1].g_iElectricDuration);
				case 6: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iHumanAbility == 0 ? "AbilityHumanSupport1" : "AbilityHumanSupport2");
			}

			if (bIsValidClient(param1, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
			{
				vElectricMenu(param1, menu.Selection);
			}
		}
		case MenuAction_Display:
		{
			char sMenuTitle[255];
			Panel panel = view_as<Panel>(param2);
			FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "ElectricMenu", param1);
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
	menu.AddItem(MT_MENU_ELECTRIC, MT_MENU_ELECTRIC);
}

public void MT_OnMenuItemSelected(int client, const char[] info)
{
	if (StrEqual(info, MT_MENU_ELECTRIC, false))
	{
		vElectricMenu(client, 0);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (MT_IsCorePluginEnabled() && bIsValidClient(victim, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && damage >= 0.5)
	{
		static char sClassname[32];
		GetEntityClassname(inflictor, sClassname, sizeof(sClassname));
		if (MT_IsTankSupported(attacker) && bIsCloneAllowed(attacker) && (g_esCache[attacker].g_iElectricHitMode == 0 || g_esCache[attacker].g_iElectricHitMode == 1) && bIsSurvivor(victim))
		{
			if ((!MT_HasAdminAccess(attacker) && !bHasAdminAccess(attacker, g_esAbility[g_esPlayer[attacker].g_iTankType].g_iAccessFlags, g_esPlayer[attacker].g_iAccessFlags)) || MT_IsAdminImmune(victim, attacker) || bIsAdminImmune(victim, g_esPlayer[attacker].g_iTankType, g_esAbility[g_esPlayer[attacker].g_iTankType].g_iImmunityFlags, g_esPlayer[victim].g_iImmunityFlags))
			{
				return Plugin_Continue;
			}

			if (StrEqual(sClassname, "weapon_tank_claw") || StrEqual(sClassname, "tank_rock"))
			{
				vElectricHit(victim, attacker, g_esCache[attacker].g_flElectricChance, g_esCache[attacker].g_iElectricHit, MT_MESSAGE_MELEE, MT_ATTACK_CLAW);
			}
		}
		else if (MT_IsTankSupported(victim) && bIsCloneAllowed(victim) && (g_esCache[victim].g_iElectricHitMode == 0 || g_esCache[victim].g_iElectricHitMode == 2) && bIsSurvivor(attacker))
		{
			if ((!MT_HasAdminAccess(victim) && !bHasAdminAccess(victim, g_esAbility[g_esPlayer[victim].g_iTankType].g_iAccessFlags, g_esPlayer[victim].g_iAccessFlags)) || MT_IsAdminImmune(attacker, victim) || bIsAdminImmune(attacker, g_esPlayer[victim].g_iTankType, g_esAbility[g_esPlayer[victim].g_iTankType].g_iImmunityFlags, g_esPlayer[attacker].g_iImmunityFlags))
			{
				return Plugin_Continue;
			}

			if (StrEqual(sClassname, "weapon_melee"))
			{
				vElectricHit(attacker, victim, g_esCache[victim].g_flElectricChance, g_esCache[victim].g_iElectricHit, MT_MESSAGE_MELEE, MT_ATTACK_MELEE);
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
	list.PushString("electricability");
	list2.PushString("electric ability");
	list3.PushString("electric_ability");
	list4.PushString("electric");
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
				g_esAbility[iIndex].g_iElectricAbility = 0;
				g_esAbility[iIndex].g_iElectricEffect = 0;
				g_esAbility[iIndex].g_iElectricMessage = 0;
				g_esAbility[iIndex].g_flElectricChance = 33.3;
				g_esAbility[iIndex].g_flElectricDamage = 1.0;
				g_esAbility[iIndex].g_iElectricDuration = 5;
				g_esAbility[iIndex].g_iElectricHit = 0;
				g_esAbility[iIndex].g_iElectricHitMode = 0;
				g_esAbility[iIndex].g_flElectricInterval = 1.0;
				g_esAbility[iIndex].g_flElectricRange = 150.0;
				g_esAbility[iIndex].g_flElectricRangeChance = 15.0;
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
					g_esPlayer[iPlayer].g_iElectricAbility = 0;
					g_esPlayer[iPlayer].g_iElectricEffect = 0;
					g_esPlayer[iPlayer].g_iElectricMessage = 0;
					g_esPlayer[iPlayer].g_flElectricChance = 0.0;
					g_esPlayer[iPlayer].g_flElectricDamage = 0.0;
					g_esPlayer[iPlayer].g_iElectricDuration = 0;
					g_esPlayer[iPlayer].g_iElectricHit = 0;
					g_esPlayer[iPlayer].g_iElectricHitMode = 0;
					g_esPlayer[iPlayer].g_flElectricInterval = 0.0;
					g_esPlayer[iPlayer].g_flElectricRange = 0.0;
					g_esPlayer[iPlayer].g_flElectricRangeChance = 0.0;
				}
			}
		}
	}
}

public void MT_OnConfigsLoaded(const char[] subsection, const char[] key, const char[] value, int type, int admin, int mode)
{
	if (mode == 3 && bIsValidClient(admin))
	{
		g_esPlayer[admin].g_iHumanAbility = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esPlayer[admin].g_iHumanAbility, value, 0, 2);
		g_esPlayer[admin].g_iHumanAmmo = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "HumanAmmo", "Human Ammo", "Human_Ammo", "hammo", g_esPlayer[admin].g_iHumanAmmo, value, 0, 999999);
		g_esPlayer[admin].g_iHumanCooldown = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "HumanCooldown", "Human Cooldown", "Human_Cooldown", "hcooldown", g_esPlayer[admin].g_iHumanCooldown, value, 0, 999999);
		g_esPlayer[admin].g_iElectricAbility = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esPlayer[admin].g_iElectricAbility, value, 0, 1);
		g_esPlayer[admin].g_iElectricEffect = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esPlayer[admin].g_iElectricEffect, value, 0, 7);
		g_esPlayer[admin].g_iElectricMessage = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esPlayer[admin].g_iElectricMessage, value, 0, 3);
		g_esPlayer[admin].g_flElectricChance = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricChance", "Electric Chance", "Electric_Chance", "chance", g_esPlayer[admin].g_flElectricChance, value, 0.0, 100.0);
		g_esPlayer[admin].g_flElectricDamage = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricDamage", "Electric Damage", "Electric_Damage", "damage", g_esPlayer[admin].g_flElectricDamage, value, 1.0, 999999.0);
		g_esPlayer[admin].g_iElectricDuration = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricDuration", "Electric Duration", "Electric_Duration", "duration", g_esPlayer[admin].g_iElectricDuration, value, 1, 999999);
		g_esPlayer[admin].g_iElectricHit = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricHit", "Electric Hit", "Electric_Hit", "hit", g_esPlayer[admin].g_iElectricHit, value, 0, 1);
		g_esPlayer[admin].g_iElectricHitMode = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricHitMode", "Electric Hit Mode", "Electric_Hit_Mode", "hitmode", g_esPlayer[admin].g_iElectricHitMode, value, 0, 2);
		g_esPlayer[admin].g_flElectricInterval = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricInterval", "Electric Interval", "Electric_Interval", "interval", g_esPlayer[admin].g_flElectricInterval, value, 0.1, 999999.0);
		g_esPlayer[admin].g_flElectricRange = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricRange", "Electric Range", "Electric_Range", "range", g_esPlayer[admin].g_flElectricRange, value, 1.0, 999999.0);
		g_esPlayer[admin].g_flElectricRangeChance = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricRangeChance", "Electric Range Chance", "Electric_Range_Chance", "rangechance", g_esPlayer[admin].g_flElectricRangeChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "electricability", false) || StrEqual(subsection, "electric ability", false) || StrEqual(subsection, "electric_ability", false) || StrEqual(subsection, "electric", false))
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
		g_esAbility[type].g_iHumanAbility = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esAbility[type].g_iHumanAbility, value, 0, 2);
		g_esAbility[type].g_iHumanAmmo = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "HumanAmmo", "Human Ammo", "Human_Ammo", "hammo", g_esAbility[type].g_iHumanAmmo, value, 0, 999999);
		g_esAbility[type].g_iHumanCooldown = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "HumanCooldown", "Human Cooldown", "Human_Cooldown", "hcooldown", g_esAbility[type].g_iHumanCooldown, value, 0, 999999);
		g_esAbility[type].g_iElectricAbility = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esAbility[type].g_iElectricAbility, value, 0, 1);
		g_esAbility[type].g_iElectricEffect = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "AbilityEffect", "Ability Effect", "Ability_Effect", "effect", g_esAbility[type].g_iElectricEffect, value, 0, 7);
		g_esAbility[type].g_iElectricMessage = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esAbility[type].g_iElectricMessage, value, 0, 3);
		g_esAbility[type].g_flElectricChance = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricChance", "Electric Chance", "Electric_Chance", "chance", g_esAbility[type].g_flElectricChance, value, 0.0, 100.0);
		g_esAbility[type].g_flElectricDamage = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricDamage", "Electric Damage", "Electric_Damage", "damage", g_esAbility[type].g_flElectricDamage, value, 1.0, 999999.0);
		g_esAbility[type].g_iElectricDuration = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricDuration", "Electric Duration", "Electric_Duration", "duration", g_esAbility[type].g_iElectricDuration, value, 1, 999999);
		g_esAbility[type].g_iElectricHit = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricHit", "Electric Hit", "Electric_Hit", "hit", g_esAbility[type].g_iElectricHit, value, 0, 1);
		g_esAbility[type].g_iElectricHitMode = iGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricHitMode", "Electric Hit Mode", "Electric_Hit_Mode", "hitmode", g_esAbility[type].g_iElectricHitMode, value, 0, 2);
		g_esAbility[type].g_flElectricInterval = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricInterval", "Electric Interval", "Electric_Interval", "interval", g_esAbility[type].g_flElectricInterval, value, 0.1, 999999.0);
		g_esAbility[type].g_flElectricRange = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricRange", "Electric Range", "Electric_Range", "range", g_esAbility[type].g_flElectricRange, value, 1.0, 999999.0);
		g_esAbility[type].g_flElectricRangeChance = flGetKeyValue(subsection, "electricability", "electric ability", "electric_ability", "electric", key, "ElectricRangeChance", "Electric Range Chance", "Electric_Range_Chance", "rangechance", g_esAbility[type].g_flElectricRangeChance, value, 0.0, 100.0);

		if (StrEqual(subsection, "electricability", false) || StrEqual(subsection, "electric ability", false) || StrEqual(subsection, "electric_ability", false) || StrEqual(subsection, "electric", false))
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
	g_esCache[tank].g_flElectricChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flElectricChance, g_esAbility[type].g_flElectricChance);
	g_esCache[tank].g_flElectricDamage = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flElectricDamage, g_esAbility[type].g_flElectricDamage);
	g_esCache[tank].g_iElectricDuration = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iElectricDuration, g_esAbility[type].g_iElectricDuration);
	g_esCache[tank].g_flElectricInterval = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flElectricInterval, g_esAbility[type].g_flElectricInterval);
	g_esCache[tank].g_flElectricRange = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flElectricRange, g_esAbility[type].g_flElectricRange);
	g_esCache[tank].g_flElectricRangeChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flElectricRangeChance, g_esAbility[type].g_flElectricRangeChance);
	g_esCache[tank].g_iElectricAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iElectricAbility, g_esAbility[type].g_iElectricAbility);
	g_esCache[tank].g_iElectricEffect = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iElectricEffect, g_esAbility[type].g_iElectricEffect);
	g_esCache[tank].g_iElectricHit = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iElectricHit, g_esAbility[type].g_iElectricHit);
	g_esCache[tank].g_iElectricHitMode = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iElectricHitMode, g_esAbility[type].g_iElectricHitMode);
	g_esCache[tank].g_iElectricMessage = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iElectricMessage, g_esAbility[type].g_iElectricMessage);
	g_esCache[tank].g_iHumanAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAbility, g_esAbility[type].g_iHumanAbility);
	g_esCache[tank].g_iHumanAmmo = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAmmo, g_esAbility[type].g_iHumanAmmo);
	g_esCache[tank].g_iHumanCooldown = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanCooldown, g_esAbility[type].g_iHumanCooldown);
	g_esPlayer[tank].g_iTankType = apply ? type : 0;
}

public void MT_OnEventFired(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(name, "player_death") || StrEqual(name, "player_spawn"))
	{
		int iTankId = event.GetInt("userid"), iTank = GetClientOfUserId(iTankId);
		if (MT_IsTankSupported(iTank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vElectricRange(iTank);
			vRemoveElectric(iTank);
		}
	}
}

public void MT_OnAbilityActivated(int tank)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || g_esCache[tank].g_iHumanAbility == 0))
	{
		return;
	}

	if (MT_IsTankSupported(tank) && (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || g_esCache[tank].g_iHumanAbility != 1) && bIsCloneAllowed(tank) && g_esCache[tank].g_iElectricAbility == 1)
	{
		vElectricAbility(tank);
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
			if (g_esCache[tank].g_iElectricAbility == 1 && g_esCache[tank].g_iHumanAbility == 1)
			{
				static int iTime;
				iTime = GetTime();

				switch (g_esPlayer[tank].g_iCooldown == -1 || g_esPlayer[tank].g_iCooldown < iTime)
				{
					case true: vElectricAbility(tank);
					case false: MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricHuman3", g_esPlayer[tank].g_iCooldown - iTime);
				}
			}
		}
	}
}

public void MT_OnChangeType(int tank, bool revert)
{
	vRemoveElectric(tank);
}

public void MT_OnPostTankSpawn(int tank)
{
	vElectricRange(tank);
}

static void vElectricAbility(int tank)
{
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
			if (bIsSurvivor(iSurvivor, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && !MT_IsAdminImmune(iSurvivor, tank) && !bIsAdminImmune(iSurvivor, g_esPlayer[tank].g_iTankType, g_esAbility[g_esPlayer[tank].g_iTankType].g_iImmunityFlags, g_esPlayer[iSurvivor].g_iImmunityFlags))
			{
				GetClientAbsOrigin(iSurvivor, flSurvivorPos);

				flDistance = GetVectorDistance(flTankPos, flSurvivorPos);
				if (flDistance <= g_esCache[tank].g_flElectricRange)
				{
					vElectricHit(iSurvivor, tank, g_esCache[tank].g_flElectricRangeChance, g_esCache[tank].g_iElectricAbility, MT_MESSAGE_RANGE, MT_ATTACK_RANGE);

					iSurvivorCount++;
				}
			}
		}

		if (iSurvivorCount == 0)
		{
			if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
			{
				MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricHuman4");
			}
		}
	}
	else if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
	{
		MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricAmmo");
	}
}

static void vElectricHit(int survivor, int tank, float chance, int enabled, int messages, int flags)
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

					MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricHuman", g_esPlayer[tank].g_iCount, g_esCache[tank].g_iHumanAmmo);

					g_esPlayer[tank].g_iCooldown = (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0) ? (iTime + g_esCache[tank].g_iHumanCooldown) : -1;
					if (g_esPlayer[tank].g_iCooldown != -1 && g_esPlayer[tank].g_iCooldown > iTime)
					{
						MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricHuman5", g_esPlayer[tank].g_iCooldown - iTime);
					}
				}

				DataPack dpElectric;
				CreateDataTimer(g_esCache[tank].g_flElectricInterval, tTimerElectric, dpElectric, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
				dpElectric.WriteCell(GetClientUserId(survivor));
				dpElectric.WriteCell(GetClientUserId(tank));
				dpElectric.WriteCell(tank);
				dpElectric.WriteCell(messages);
				dpElectric.WriteCell(enabled);
				dpElectric.WriteCell(GetTime());

				static char sEffect[32];
				vGetRandomParticle(sEffect, sizeof(sEffect));
				vAttachParticle(survivor, sEffect, 2.0, 30.0);

				vEffect(survivor, tank, g_esCache[tank].g_iElectricEffect, flags);

				if (g_esCache[tank].g_iElectricMessage & messages)
				{
					static char sTankName[33];
					MT_GetTankName(tank, sTankName);
					MT_PrintToChatAll("%s %t", MT_TAG2, "Electric", sTankName, survivor);
				}
			}
			else if ((flags & MT_ATTACK_RANGE) && (g_esPlayer[tank].g_iCooldown == -1 || g_esPlayer[tank].g_iCooldown < iTime))
			{
				if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && !g_esPlayer[tank].g_bFailed)
				{
					g_esPlayer[tank].g_bFailed = true;

					MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricHuman2");
				}
			}
		}
		else if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1 && !g_esPlayer[tank].g_bNoAmmo)
		{
			g_esPlayer[tank].g_bNoAmmo = true;

			MT_PrintToChat(tank, "%s %t", MT_TAG3, "ElectricAmmo");
		}
	}
}

static void vElectricRange(int tank)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE) && bIsCloneAllowed(tank) && g_esCache[tank].g_iElectricAbility == 1)
	{
		if (MT_HasAdminAccess(tank) || bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
		{
			static char sEffect[32];
			vGetRandomParticle(sEffect, sizeof(sEffect));
			vAttachParticle(tank, sEffect, 2.0, 30.0);
		}
	}
}

static void vGetRandomParticle(char[] buffer, int size)
{
	switch (GetRandomInt(1, 7))
	{
		case 1: strcopy(buffer, size, PARTICLE_ELECTRICITY);
		case 2: strcopy(buffer, size, PARTICLE_ELECTRICITY2);
		case 3: strcopy(buffer, size, PARTICLE_ELECTRICITY3);
		case 4, 6: strcopy(buffer, size, (bIsValidGame() ? PARTICLE_ELECTRICITY4 : PARTICLE_ELECTRICITY6));
		case 5, 7: strcopy(buffer, size, (bIsValidGame() ? PARTICLE_ELECTRICITY5 : PARTICLE_ELECTRICITY7));
	}
}

static void vRemoveElectric(int tank)
{
	for (int iSurvivor = 1; iSurvivor <= MaxClients; iSurvivor++)
	{
		if (bIsSurvivor(iSurvivor, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && g_esPlayer[iSurvivor].g_bAffected && g_esPlayer[iSurvivor].g_iOwner == tank)
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

	if (g_esCache[tank].g_iElectricMessage & messages)
	{
		MT_PrintToChatAll("%s %t", MT_TAG2, "Electric2", survivor);
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

public Action tTimerElectric(Handle timer, DataPack pack)
{
	pack.Reset();

	static int iSurvivor;
	iSurvivor = GetClientOfUserId(pack.ReadCell());
	if (!MT_IsCorePluginEnabled() || !bIsSurvivor(iSurvivor))
	{
		g_esPlayer[iSurvivor].g_bAffected = false;
		g_esPlayer[iSurvivor].g_iOwner = 0;

		return Plugin_Stop;
	}

	static int iTank, iType, iMessage;
	iTank = GetClientOfUserId(pack.ReadCell());
	iType = pack.ReadCell();
	iMessage = pack.ReadCell();
	if (!MT_IsTankSupported(iTank) || !MT_HasAdminAccess(iTank) || !bHasAdminAccess(iTank, g_esAbility[g_esPlayer[iTank].g_iTankType].g_iAccessFlags, g_esPlayer[iTank].g_iAccessFlags) || !MT_IsTypeEnabled(iTank) || !bIsCloneAllowed(iTank) || iType != iTank || MT_IsAdminImmune(iSurvivor, iTank) || bIsAdminImmune(iSurvivor, g_esPlayer[iTank].g_iTankType, g_esAbility[g_esPlayer[iTank].g_iTankType].g_iImmunityFlags, g_esPlayer[iSurvivor].g_iImmunityFlags) || !g_esPlayer[iSurvivor].g_bAffected)
	{
		vReset2(iSurvivor, iTank, iMessage);

		return Plugin_Stop;
	}

	static int iElectricEnabled, iTime;
	iElectricEnabled = pack.ReadCell();
	iTime = pack.ReadCell();
	if (iElectricEnabled == 0 || (iTime + g_esCache[iTank].g_iElectricDuration) < GetTime())
	{
		vReset2(iSurvivor, iTank, iMessage);

		return Plugin_Stop;
	}

	vDamageEntity(iSurvivor, iTank, g_esCache[iTank].g_flElectricDamage, "1024");

	static char sEffect[32];
	vGetRandomParticle(sEffect, sizeof(sEffect));
	vAttachParticle(iSurvivor, sEffect, 2.0, 30.0);

	EmitSoundToAll(g_sZapSounds[GetRandomInt(0, 7)], iSurvivor);

	return Plugin_Continue;
}