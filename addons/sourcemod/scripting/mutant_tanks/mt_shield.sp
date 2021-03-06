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
	name = "[MT] Shield Ability",
	author = MT_AUTHOR,
	description = "The Mutant Tank protects itself with a shield and throws propane tanks or gas cans.",
	version = MT_VERSION,
	url = MT_URL
};

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!bIsValidGame(false) && !bIsValidGame())
	{
		strcopy(error, err_max, "\"[MT] Shield Ability\" only supports Left 4 Dead 1 & 2.");

		return APLRes_SilentFailure;
	}

	g_bLateLoad = late;

	return APLRes_Success;
}

#define MODEL_GASCAN "models/props_junk/gascan001a.mdl"
#define MODEL_PROPANETANK "models/props_junk/propanecanister001a.mdl"
#define MODEL_SHIELD "models/props_unique/airport/atlas_break_ball.mdl"

#define MT_MENU_SHIELD "Shield Ability"

ConVar g_cvMTTankThrowForce;

enum struct esPlayer
{
	bool g_bActivated;

	char g_sShieldHealthChars[4];

	float g_flHealth;
	float g_flShieldChance;
	float g_flShieldHealth;

	int g_iAccessFlags;
	int g_iCooldown;
	int g_iCount;
	int g_iDuration;
	int g_iDuration2;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iHumanDuration;
	int g_iHumanMode;
	int g_iImmunityFlags;
	int g_iShield;
	int g_iShieldAbility;
	int g_iShieldColor[4];
	int g_iShieldDelay;
	int g_iShieldDisplayHP;
	int g_iShieldDisplayHPType;
	int g_iShieldMessage;
	int g_iShieldType;
	int g_iTankType;
}

esPlayer g_esPlayer[MAXPLAYERS + 1];

enum struct esAbility
{
	char g_sShieldHealthChars[4];

	float g_flShieldChance;
	float g_flShieldHealth;

	int g_iAccessFlags;
	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iHumanDuration;
	int g_iHumanMode;
	int g_iImmunityFlags;
	int g_iShieldAbility;
	int g_iShieldColor[4];
	int g_iShieldDelay;
	int g_iShieldDisplayHP;
	int g_iShieldDisplayHPType;
	int g_iShieldMessage;
	int g_iShieldType;
}

esAbility g_esAbility[MT_MAXTYPES + 1];

enum struct esCache
{
	char g_sShieldHealthChars[4];

	float g_flShieldChance;
	float g_flShieldHealth;

	int g_iHumanAbility;
	int g_iHumanAmmo;
	int g_iHumanCooldown;
	int g_iHumanDuration;
	int g_iHumanMode;
	int g_iShieldAbility;
	int g_iShieldColor[4];
	int g_iShieldDelay;
	int g_iShieldDisplayHP;
	int g_iShieldDisplayHPType;
	int g_iShieldMessage;
	int g_iShieldType;
}

esCache g_esCache[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mutant_tanks.phrases");

	RegConsoleCmd("sm_mt_shield", cmdShieldInfo, "View information about the Shield ability.");

	g_cvMTTankThrowForce = FindConVar("z_tank_throw_force");

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
	PrecacheModel(MODEL_GASCAN, true);
	PrecacheModel(MODEL_SHIELD, true);

	vReset();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	vReset2(client);
}

public void OnClientDisconnect_Post(int client)
{
	vReset2(client);
}

public void OnMapEnd()
{
	vReset();
}

public Action cmdShieldInfo(int client, int args)
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
		case false: vShieldMenu(client, 0);
	}

	return Plugin_Handled;
}

static void vShieldMenu(int client, int item)
{
	Menu mAbilityMenu = new Menu(iShieldMenuHandler, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	mAbilityMenu.SetTitle("Shield Ability Information");
	mAbilityMenu.AddItem("Status", "Status");
	mAbilityMenu.AddItem("Ammunition", "Ammunition");
	mAbilityMenu.AddItem("Buttons", "Buttons");
	mAbilityMenu.AddItem("Button Mode", "Button Mode");
	mAbilityMenu.AddItem("Cooldown", "Cooldown");
	mAbilityMenu.AddItem("Details", "Details");
	mAbilityMenu.AddItem("Duration", "Duration");
	mAbilityMenu.AddItem("Human Support", "Human Support");
	mAbilityMenu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int iShieldMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End: delete menu;
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iShieldAbility == 0 ? "AbilityStatus1" : "AbilityStatus2");
				case 1: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityAmmo", g_esCache[param1].g_iHumanAmmo - g_esPlayer[param1].g_iCount, g_esCache[param1].g_iHumanAmmo);
				case 2: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityButtons");
				case 3: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iHumanMode == 0 ? "AbilityButtonMode1" : "AbilityButtonMode2");
				case 4: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityCooldown", g_esCache[param1].g_iHumanCooldown);
				case 5: MT_PrintToChat(param1, "%s %t", MT_TAG3, "ShieldDetails");
				case 6: MT_PrintToChat(param1, "%s %t", MT_TAG3, "AbilityDuration2", g_esCache[param1].g_iHumanDuration);
				case 7: MT_PrintToChat(param1, "%s %t", MT_TAG3, g_esCache[param1].g_iHumanAbility == 0 ? "AbilityHumanSupport1" : "AbilityHumanSupport2");
			}

			if (bIsValidClient(param1, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
			{
				vShieldMenu(param1, menu.Selection);
			}
		}
		case MenuAction_Display:
		{
			char sMenuTitle[255];
			Panel panel = view_as<Panel>(param2);
			FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "ShieldMenu", param1);
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
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "ButtonMode", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 4:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Cooldown", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 5:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Details", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 6:
				{
					FormatEx(sMenuOption, sizeof(sMenuOption), "%T", "Duration", param1);

					return RedrawMenuItem(sMenuOption);
				}
				case 7:
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
	menu.AddItem(MT_MENU_SHIELD, MT_MENU_SHIELD);
}

public void MT_OnMenuItemSelected(int client, const char[] info)
{
	if (StrEqual(info, MT_MENU_SHIELD, false))
	{
		vShieldMenu(client, 0);
	}
}

public void OnGameFrame()
{
	if (MT_IsCorePluginEnabled())
	{
		static char sClassname[32], sHealthBar[51], sSet[2][2], sTankName[33];
		static float flPercentage;
		static int iTarget;
		for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
		{
			if (bIsValidClient(iPlayer, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT))
			{
				iTarget = GetClientAimTarget(iPlayer, false);
				if (bIsValidEntity(iTarget))
				{
					GetEntityClassname(iTarget, sClassname, sizeof(sClassname));
					if (StrEqual(sClassname, "player") && bIsTank(iTarget) && g_esPlayer[iTarget].g_bActivated && g_esPlayer[iTarget].g_flHealth > 0.0 && g_esCache[iTarget].g_flShieldHealth > 0.0)
					{
						MT_GetTankName(iTarget, sTankName);

						sHealthBar[0] = '\0';
						flPercentage = (g_esPlayer[iTarget].g_flHealth / g_esCache[iTarget].g_flShieldHealth) * 100;

						ReplaceString(g_esCache[iTarget].g_sShieldHealthChars, sizeof(esCache::g_sShieldHealthChars), " ", "");
						ExplodeString(g_esCache[iTarget].g_sShieldHealthChars, ",", sSet, sizeof(sSet), sizeof(sSet[]));

						for (int iCount = 0; iCount < (g_esPlayer[iTarget].g_flHealth / g_esCache[iTarget].g_flShieldHealth) * sizeof(sHealthBar) - 1 && iCount < sizeof(sHealthBar) - 1; iCount++)
						{
							StrCat(sHealthBar, sizeof(sHealthBar), sSet[0]);
						}

						for (int iCount = 0; iCount < sizeof(sHealthBar) - 1; iCount++)
						{
							StrCat(sHealthBar, sizeof(sHealthBar), sSet[1]);
						}

						switch (g_esCache[iTarget].g_iShieldDisplayHPType)
						{
							case 1:
							{
								switch (g_esCache[iTarget].g_iShieldDisplayHP)
								{
									case 1: PrintHintText(iPlayer, "%t", "ShieldOwner", sTankName);
									case 2: PrintHintText(iPlayer, "Shield: %.0f HP", g_esPlayer[iTarget].g_flHealth);
									case 3: PrintHintText(iPlayer, "Shield: %.0f/%.0f HP (%.0f%s)", g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%");
									case 4: PrintHintText(iPlayer, "Shield\nHP: |-<%s>-|", sHealthBar);
									case 5: PrintHintText(iPlayer, "%t (%.0f HP)", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth);
									case 6: PrintHintText(iPlayer, "%t [%.0f/%.0f HP (%.0f%s)]", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%");
									case 7: PrintHintText(iPlayer, "%t\nHP: |-<%s>-|", "ShieldOwner", sTankName, sHealthBar);
									case 8: PrintHintText(iPlayer, "Shield: %.0f HP\nHP: |-<%s>-|", g_esPlayer[iTarget].g_flHealth, sHealthBar);
									case 9: PrintHintText(iPlayer, "Shield: %.0f/%.0f HP (%.0f%s)\nHP: |-<%s>-|", g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%", sHealthBar);
									case 10: PrintHintText(iPlayer, "%t (%.0f HP)\nHP: |-<%s>-|", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth, sHealthBar);
									case 11: PrintHintText(iPlayer, "%t [%.0f/%.0f HP (%.0f%s)]\nHP: |-<%s>-|", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%", sHealthBar);
								}
							}
							case 2:
							{
								switch (g_esCache[iTarget].g_iShieldDisplayHP)
								{
									case 1: PrintCenterText(iPlayer, "%t", "ShieldOwner", sTankName);
									case 2: PrintCenterText(iPlayer, "Shield: %.0f HP", g_esPlayer[iTarget].g_flHealth);
									case 3: PrintCenterText(iPlayer, "Shield: %.0f/%.0f HP (%.0f%s)", g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%");
									case 4: PrintCenterText(iPlayer, "Shield\nHP: |-<%s>-|", sHealthBar);
									case 5: PrintCenterText(iPlayer, "%t (%.0f HP)", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth);
									case 6: PrintCenterText(iPlayer, "%t [%.0f/%.0f HP (%.0f%s)]", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%");
									case 7: PrintCenterText(iPlayer, "%t\nHP: |-<%s>-|", "ShieldOwner", sTankName, sHealthBar);
									case 8: PrintCenterText(iPlayer, "Shield: %.0f HP\nHP: |-<%s>-|", g_esPlayer[iTarget].g_flHealth, sHealthBar);
									case 9: PrintCenterText(iPlayer, "Shield: %.0f/%.0f HP (%.0f%s)\nHP: |-<%s>-|", g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%", sHealthBar);
									case 10: PrintCenterText(iPlayer, "%t (%.0f HP)\nHP: |-<%s>-|", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth, sHealthBar);
									case 11: PrintCenterText(iPlayer, "%t [%.0f/%.0f HP (%.0f%s)]\nHP: |-<%s>-|", "ShieldOwner", sTankName, g_esPlayer[iTarget].g_flHealth, g_esCache[iTarget].g_flShieldHealth, flPercentage, "%%", sHealthBar);
								}
							}
						}
					}
				}
			}
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!MT_IsCorePluginEnabled() || !MT_IsTankSupported(client) || (MT_IsTankSupported(client, MT_CHECK_FAKECLIENT) && g_esCache[client].g_iHumanMode == 1) || (g_esPlayer[client].g_iDuration == -1 && g_esPlayer[client].g_iDuration2 == -1))
	{
		return Plugin_Continue;
	}

	static int iTime;
	iTime = GetTime();
	if (g_esPlayer[client].g_bActivated && g_esPlayer[client].g_iDuration != -1 && g_esPlayer[client].g_iDuration < iTime)
	{
		if (MT_IsTankSupported(client, MT_CHECK_FAKECLIENT) && (MT_HasAdminAccess(client) || bHasAdminAccess(client, g_esAbility[g_esPlayer[client].g_iTankType].g_iAccessFlags, g_esPlayer[client].g_iAccessFlags)) && g_esCache[client].g_iHumanAbility == 1 && g_esCache[client].g_iHumanMode == 0 && (g_esPlayer[client].g_iCooldown == -1 || g_esPlayer[client].g_iCooldown < iTime))
		{
			vReset3(client);
		}

		vShieldAbility(client, false);
	}
	else if (g_esPlayer[client].g_iDuration2 != -1 && g_esPlayer[client].g_iDuration2 < iTime)
	{
		vShieldAbility(client, true);
	}

	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (MT_IsCorePluginEnabled() && bIsValidClient(victim, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && damage >= 0.5)
	{
		if (MT_IsTankSupported(victim) && bIsCloneAllowed(victim) && bIsSurvivor(attacker) && g_esPlayer[victim].g_bActivated)
		{
			if ((!MT_HasAdminAccess(victim) && !bHasAdminAccess(victim, g_esAbility[g_esPlayer[victim].g_iTankType].g_iAccessFlags, g_esPlayer[victim].g_iAccessFlags)) || MT_IsAdminImmune(attacker, victim) || bIsAdminImmune(attacker, g_esPlayer[victim].g_iTankType, g_esAbility[g_esPlayer[victim].g_iTankType].g_iImmunityFlags, g_esPlayer[attacker].g_iImmunityFlags))
			{
				vShieldAbility(victim, false);

				return Plugin_Continue;
			}

			if (((damagetype & DMG_BULLET) && g_esCache[victim].g_iShieldType == 0) || (((damagetype & DMG_BLAST) || (damagetype & DMG_BLAST_SURFACE) || (damagetype & DMG_AIRBOAT)
				|| (damagetype & DMG_PLASMA)) && g_esCache[victim].g_iShieldType == 1) || ((damagetype & DMG_BURN) && g_esCache[victim].g_iShieldType == 2) || (((damagetype & DMG_SLASH)
				|| (damagetype & DMG_CLUB)) && g_esCache[victim].g_iShieldType == 3))
			{
				g_esPlayer[victim].g_flHealth -= damage;
				if (g_esCache[victim].g_flShieldHealth == 0.0 || g_esPlayer[victim].g_flHealth < 1.0)
				{
					vShieldAbility(victim, false);
				}
			}

			return Plugin_Handled;
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
	list.PushString("shieldability");
	list2.PushString("shield ability");
	list3.PushString("shield_ability");
	list4.PushString("shield");
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
				g_esAbility[iIndex].g_iHumanDuration = 5;
				g_esAbility[iIndex].g_iHumanMode = 1;
				g_esAbility[iIndex].g_iShieldAbility = 0;
				g_esAbility[iIndex].g_iShieldMessage = 0;
				g_esAbility[iIndex].g_flShieldChance = 33.3;
				g_esAbility[iIndex].g_iShieldDelay = 5;
				g_esAbility[iIndex].g_iShieldDisplayHP = 11;
				g_esAbility[iIndex].g_iShieldDisplayHPType = 2;
				g_esAbility[iIndex].g_flShieldHealth = 0.0;
				g_esAbility[iIndex].g_sShieldHealthChars = "],=";
				g_esAbility[iIndex].g_iShieldType = 1;

				for (int iPos = 0; iPos < sizeof(esAbility::g_iShieldColor); iPos++)
				{
					g_esAbility[iIndex].g_iShieldColor[iPos] = -1;
				}
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
					g_esPlayer[iPlayer].g_iHumanDuration = 0;
					g_esPlayer[iPlayer].g_iHumanMode = 0;
					g_esPlayer[iPlayer].g_iShieldAbility = 0;
					g_esPlayer[iPlayer].g_iShieldMessage = 0;
					g_esPlayer[iPlayer].g_flShieldChance = 0.0;
					g_esPlayer[iPlayer].g_iShieldDelay = 0;
					g_esPlayer[iPlayer].g_iShieldDisplayHP = 0;
					g_esPlayer[iPlayer].g_iShieldDisplayHPType = 0;
					g_esPlayer[iPlayer].g_flShieldHealth = 0.0;
					g_esPlayer[iPlayer].g_sShieldHealthChars[0] = '\0';
					g_esPlayer[iPlayer].g_iShieldType = 0;

					for (int iPos = 0; iPos < sizeof(esPlayer::g_iShieldColor); iPos++)
					{
						g_esPlayer[iPlayer].g_iShieldColor[iPos] = -1;
					}
				}
			}
		}
	}
}

public void MT_OnConfigsLoaded(const char[] subsection, const char[] key, const char[] value, int type, int admin, int mode)
{
	if (mode == 3 && bIsValidClient(admin))
	{
		g_esPlayer[admin].g_iHumanAbility = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esPlayer[admin].g_iHumanAbility, value, 0, 2);
		g_esPlayer[admin].g_iHumanAmmo = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanAmmo", "Human Ammo", "Human_Ammo", "hammo", g_esPlayer[admin].g_iHumanAmmo, value, 0, 999999);
		g_esPlayer[admin].g_iHumanCooldown = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanCooldown", "Human Cooldown", "Human_Cooldown", "hcooldown", g_esPlayer[admin].g_iHumanCooldown, value, 0, 999999);
		g_esPlayer[admin].g_iHumanDuration = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanDuration", "Human Duration", "Human_Duration", "hduration", g_esPlayer[admin].g_iHumanDuration, value, 1, 999999);
		g_esPlayer[admin].g_iHumanMode = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanMode", "Human Mode", "Human_Mode", "hmode", g_esPlayer[admin].g_iHumanMode, value, 0, 1);
		g_esPlayer[admin].g_iShieldAbility = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esPlayer[admin].g_iShieldAbility, value, 0, 1);
		g_esPlayer[admin].g_iShieldMessage = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esPlayer[admin].g_iShieldMessage, value, 0, 1);
		g_esPlayer[admin].g_flShieldChance = flGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldChance", "Shield Chance", "Shield_Chance", "chance", g_esPlayer[admin].g_flShieldChance, value, 0.0, 100.0);
		g_esPlayer[admin].g_iShieldDelay = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldDelay", "Shield Delay", "Shield_Delay", "delay", g_esPlayer[admin].g_iShieldDelay, value, 1, 999999);
		g_esPlayer[admin].g_iShieldDisplayHP = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldDisplayHealth", "Shield Display Health", "Shield_Display_Health", "displayhp", g_esPlayer[admin].g_iShieldDisplayHP, value, 0, 11);
		g_esPlayer[admin].g_iShieldDisplayHPType = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldDisplayHealthType", "Shield Display Health Type", "Shield_Display_Health_Type", "displaytype", g_esPlayer[admin].g_iShieldDisplayHPType, value, 0, 2);
		g_esPlayer[admin].g_flShieldHealth = flGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldHealth", "Shield Health", "Shield_Health", "health", g_esPlayer[admin].g_flShieldHealth, value, 0.0, 999999.0);
		g_esPlayer[admin].g_iShieldType = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldType", "Shield Type", "Shield_Type", "type", g_esPlayer[admin].g_iShieldType, value, 0, 3);

		if (StrEqual(subsection, "shieldability", false) || StrEqual(subsection, "shield ability", false) || StrEqual(subsection, "shield_ability", false) || StrEqual(subsection, "shield", false))
		{
			if (StrEqual(key, "AccessFlags", false) || StrEqual(key, "Access Flags", false) || StrEqual(key, "Access_Flags", false) || StrEqual(key, "access", false))
			{
				g_esPlayer[admin].g_iAccessFlags = ReadFlagString(value);
			}
			else if (StrEqual(key, "ImmunityFlags", false) || StrEqual(key, "Immunity Flags", false) || StrEqual(key, "Immunity_Flags", false) || StrEqual(key, "immunity", false))
			{
				g_esPlayer[admin].g_iImmunityFlags = ReadFlagString(value);
			}
			else if (StrEqual(key, "ShieldColor", false) || StrEqual(key, "Shield Color", false) || StrEqual(key, "Shield_Color", false) || StrEqual(key, "color", false))
			{
				static char sSet[4][4], sValue[16];
				strcopy(sValue, sizeof(sValue), value);
				ReplaceString(sValue, sizeof(sValue), " ", "");
				ExplodeString(sValue, ",", sSet, sizeof(sSet), sizeof(sSet[]));

				for (int iPos = 0; iPos < sizeof(sSet); iPos++)
				{
					if (sSet[iPos][0] == '\0')
					{
						continue;
					}

					g_esPlayer[admin].g_iShieldColor[iPos] = (StringToInt(sSet[iPos]) >= 0) ? iClamp(StringToInt(sSet[iPos]), 0, 255) : GetRandomInt(0, 255);
				}
			}
			else if (StrEqual(key, "ShieldHealthCharacters", false) || StrEqual(key, "Shield Health Characters", false) || StrEqual(key, "Shield_Characters", false) || StrEqual(key, "hpchars", false))
			{
				strcopy(g_esPlayer[admin].g_sShieldHealthChars, sizeof(esPlayer::g_sShieldHealthChars), value);
			}
		}
	}

	if (mode < 3 && type > 0)
	{
		g_esAbility[type].g_iHumanAbility = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanAbility", "Human Ability", "Human_Ability", "human", g_esAbility[type].g_iHumanAbility, value, 0, 2);
		g_esAbility[type].g_iHumanAmmo = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanAmmo", "Human Ammo", "Human_Ammo", "hammo", g_esAbility[type].g_iHumanAmmo, value, 0, 999999);
		g_esAbility[type].g_iHumanCooldown = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanCooldown", "Human Cooldown", "Human_Cooldown", "hcooldown", g_esAbility[type].g_iHumanCooldown, value, 0, 999999);
		g_esAbility[type].g_iHumanDuration = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanDuration", "Human Duration", "Human_Duration", "hduration", g_esAbility[type].g_iHumanDuration, value, 1, 999999);
		g_esAbility[type].g_iHumanMode = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "HumanMode", "Human Mode", "Human_Mode", "hmode", g_esAbility[type].g_iHumanMode, value, 0, 1);
		g_esAbility[type].g_iShieldAbility = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "AbilityEnabled", "Ability Enabled", "Ability_Enabled", "enabled", g_esAbility[type].g_iShieldAbility, value, 0, 1);
		g_esAbility[type].g_iShieldMessage = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "AbilityMessage", "Ability Message", "Ability_Message", "message", g_esAbility[type].g_iShieldMessage, value, 0, 1);
		g_esAbility[type].g_flShieldChance = flGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldChance", "Shield Chance", "Shield_Chance", "chance", g_esAbility[type].g_flShieldChance, value, 0.0, 100.0);
		g_esAbility[type].g_iShieldDelay = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldDelay", "Shield Delay", "Shield_Delay", "delay", g_esAbility[type].g_iShieldDelay, value, 1, 999999);
		g_esAbility[type].g_iShieldDisplayHP = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldDisplayHealth", "Shield Display Health", "Shield_Display_Health", "displayhp", g_esAbility[type].g_iShieldDisplayHP, value, 0, 11);
		g_esAbility[type].g_iShieldDisplayHPType = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldDisplayHealthType", "Shield Display Health Type", "Shield_Display_Health_Type", "displaytype", g_esAbility[type].g_iShieldDisplayHPType, value, 0, 2);
		g_esAbility[type].g_flShieldHealth = flGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldHealth", "Shield Health", "Shield_Health", "health", g_esAbility[type].g_flShieldHealth, value, 0.0, 999999.0);
		g_esAbility[type].g_iShieldType = iGetKeyValue(subsection, "shieldability", "shield ability", "shield_ability", "shield", key, "ShieldType", "Shield Type", "Shield_Type", "type", g_esAbility[type].g_iShieldType, value, 0, 3);

		if (StrEqual(subsection, "shieldability", false) || StrEqual(subsection, "shield ability", false) || StrEqual(subsection, "shield_ability", false) || StrEqual(subsection, "shield", false))
		{
			if (StrEqual(key, "AccessFlags", false) || StrEqual(key, "Access Flags", false) || StrEqual(key, "Access_Flags", false) || StrEqual(key, "access", false))
			{
				g_esAbility[type].g_iAccessFlags = ReadFlagString(value);
			}
			else if (StrEqual(key, "ImmunityFlags", false) || StrEqual(key, "Immunity Flags", false) || StrEqual(key, "Immunity_Flags", false) || StrEqual(key, "immunity", false))
			{
				g_esAbility[type].g_iImmunityFlags = ReadFlagString(value);
			}
			else if (StrEqual(key, "ShieldColor", false) || StrEqual(key, "Shield Color", false) || StrEqual(key, "Shield_Color", false) || StrEqual(key, "color", false))
			{
				static char sSet[4][4], sValue[16];
				strcopy(sValue, sizeof(sValue), value);
				ReplaceString(sValue, sizeof(sValue), " ", "");
				ExplodeString(sValue, ",", sSet, sizeof(sSet), sizeof(sSet[]));

				for (int iPos = 0; iPos < sizeof(sSet); iPos++)
				{
					if (sSet[iPos][0] == '\0')
					{
						continue;
					}

					g_esAbility[type].g_iShieldColor[iPos] = (StringToInt(sSet[iPos]) >= 0) ? iClamp(StringToInt(sSet[iPos]), 0, 255) : GetRandomInt(0, 255);
				}
			}
			else if (StrEqual(key, "ShieldHealthCharacters", false) || StrEqual(key, "Shield Health Characters", false) || StrEqual(key, "Shield_Characters", false) || StrEqual(key, "hpchars", false))
			{
				strcopy(g_esAbility[type].g_sShieldHealthChars, sizeof(esAbility::g_sShieldHealthChars), value);
			}
		}
	}
}

public void MT_OnSettingsCached(int tank, bool apply, int type)
{
	bool bHuman = MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT);
	g_esCache[tank].g_flShieldChance = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShieldChance, g_esAbility[type].g_flShieldChance);
	g_esCache[tank].g_iHumanAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAbility, g_esAbility[type].g_iHumanAbility);
	g_esCache[tank].g_iHumanAmmo = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanAmmo, g_esAbility[type].g_iHumanAmmo);
	g_esCache[tank].g_iHumanCooldown = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanCooldown, g_esAbility[type].g_iHumanCooldown);
	g_esCache[tank].g_iHumanDuration = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanDuration, g_esAbility[type].g_iHumanDuration);
	g_esCache[tank].g_iHumanMode = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iHumanMode, g_esAbility[type].g_iHumanMode);
	g_esCache[tank].g_iShieldAbility = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldAbility, g_esAbility[type].g_iShieldAbility);
	g_esCache[tank].g_iShieldDelay = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldDelay, g_esAbility[type].g_iShieldDelay);
	g_esCache[tank].g_iShieldDisplayHP = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldDisplayHP, g_esAbility[type].g_iShieldDisplayHP);
	g_esCache[tank].g_iShieldDisplayHPType = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldDisplayHPType, g_esAbility[type].g_iShieldDisplayHPType);
	g_esCache[tank].g_flShieldHealth = flGetSettingValue(apply, bHuman, g_esPlayer[tank].g_flShieldHealth, g_esAbility[type].g_flShieldHealth);
	vGetSettingValue(apply, bHuman, g_esCache[tank].g_sShieldHealthChars, sizeof(esCache::g_sShieldHealthChars), g_esPlayer[tank].g_sShieldHealthChars, g_esAbility[type].g_sShieldHealthChars);
	g_esCache[tank].g_iShieldMessage = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldMessage, g_esAbility[type].g_iShieldMessage);
	g_esCache[tank].g_iShieldType = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldType, g_esAbility[type].g_iShieldType);
	g_esPlayer[tank].g_iTankType = apply ? type : 0;

	for (int iPos = 0; iPos < sizeof(esCache::g_iShieldColor); iPos++)
	{
		g_esCache[tank].g_iShieldColor[iPos] = iGetSettingValue(apply, bHuman, g_esPlayer[tank].g_iShieldColor[iPos], g_esAbility[type].g_iShieldColor[iPos], true);
	}
}

public void MT_OnPluginEnd()
{
	for (int iTank = 1; iTank <= MaxClients; iTank++)
	{
		if (bIsTank(iTank, MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE) && g_esPlayer[iTank].g_bActivated)
		{
			vRemoveShield(iTank);
		}
	}
}

public void MT_OnEventFired(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(name, "bot_player_replace"))
	{
		int iBotId = event.GetInt("bot"), iBot = GetClientOfUserId(iBotId),
			iTankId = event.GetInt("player"), iTank = GetClientOfUserId(iTankId);
		if (bIsValidClient(iBot) && bIsTank(iTank))
		{
			vRemoveShield(iBot);
			vReset2(iBot);
		}
	}
	else if (StrEqual(name, "player_bot_replace"))
	{
		int iTankId = event.GetInt("player"), iTank = GetClientOfUserId(iTankId),
			iBotId = event.GetInt("bot"), iBot = GetClientOfUserId(iBotId);
		if (bIsValidClient(iTank) && bIsTank(iBot))
		{
			vRemoveShield(iTank);
			vReset2(iTank);
		}
	}
	else if (StrEqual(name, "player_death") || StrEqual(name, "player_incapacitated") || StrEqual(name, "player_spawn"))
	{
		int iTankId = event.GetInt("userid"), iTank = GetClientOfUserId(iTankId);
		if (MT_IsTankSupported(iTank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vRemoveShield(iTank);
			vReset2(iTank);
		}
	}
}

public void MT_OnAbilityActivated(int tank)
{
	if ((MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || g_esCache[tank].g_iHumanAbility == 0)) || bIsPlayerIncapacitated(tank))
	{
		return;
	}

	if (MT_IsTankSupported(tank) && (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || g_esCache[tank].g_iHumanAbility != 1) && bIsCloneAllowed(tank) && g_esCache[tank].g_iShieldAbility == 1 && !g_esPlayer[tank].g_bActivated)
	{
		vShieldAbility(tank, true);
	}
}

public void MT_OnButtonPressed(int tank, int button)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && bIsCloneAllowed(tank))
	{
		if ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || bIsPlayerIncapacitated(tank))
		{
			return;
		}

		if (button & MT_MAIN_KEY)
		{
			if (g_esCache[tank].g_iShieldAbility == 1 && g_esCache[tank].g_iHumanAbility == 1)
			{
				static int iTime;
				iTime = GetTime();
				static bool bRecharging;
				bRecharging = g_esPlayer[tank].g_iCooldown != -1 && g_esPlayer[tank].g_iCooldown > iTime;

				switch (g_esCache[tank].g_iHumanMode)
				{
					case 0:
					{
						if (!g_esPlayer[tank].g_bActivated && !bRecharging)
						{
							vShieldAbility(tank, true);
						}
						else if (g_esPlayer[tank].g_bActivated)
						{
							MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman3");
						}
						else if (bRecharging)
						{
							MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman4", g_esPlayer[tank].g_iCooldown - iTime);
						}
					}
					case 1:
					{
						if (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0)
						{
							if (!g_esPlayer[tank].g_bActivated && !bRecharging)
							{
								g_esPlayer[tank].g_bActivated = true;
								g_esPlayer[tank].g_iCount++;

								g_esPlayer[tank].g_iShield = CreateEntityByName("prop_dynamic");
								if (bIsValidEntity(g_esPlayer[tank].g_iShield))
								{
									vShield(tank);
								}

								MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman", g_esPlayer[tank].g_iCount, g_esCache[tank].g_iHumanAmmo);
							}
							else if (g_esPlayer[tank].g_bActivated)
							{
								MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman3");
							}
							else if (bRecharging)
							{
								MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman4", g_esPlayer[tank].g_iCooldown - iTime);
							}
						}
						else
						{
							MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldAmmo");
						}
					}
				}
			}
		}
	}
}

public void MT_OnButtonReleased(int tank, int button)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT))
	{
		if (button & MT_MAIN_KEY)
		{
			if (g_esCache[tank].g_iHumanMode == 1 && g_esPlayer[tank].g_bActivated && (g_esPlayer[tank].g_iCooldown == -1 || g_esPlayer[tank].g_iCooldown < GetTime()))
			{
				g_esPlayer[tank].g_bActivated = false;

				vRemoveShield(tank);
				vReset3(tank);
			}
		}
	}
}

public void MT_OnChangeType(int tank, bool revert)
{
	if (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
	{
		vRemoveShield(tank);
	}

	vReset2(tank, revert);
}

public void MT_OnRockThrow(int tank, int rock)
{
	if (MT_IsTankSupported(tank) && bIsCloneAllowed(tank) && g_esCache[tank].g_iShieldAbility == 1 && GetRandomFloat(0.1, 100.0) <= g_esCache[tank].g_flShieldChance)
	{
		if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
		{
			return;
		}

		DataPack dpShieldThrow;
		CreateDataTimer(0.1, tTimerShieldThrow, dpShieldThrow, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		dpShieldThrow.WriteCell(EntIndexToEntRef(rock));
		dpShieldThrow.WriteCell(GetClientUserId(tank));
		dpShieldThrow.WriteCell(g_esPlayer[tank].g_iTankType);
	}
}

static void vRemoveShield(int tank)
{
	if (bIsValidEntRef(g_esPlayer[tank].g_iShield))
	{
		g_esPlayer[tank].g_iShield = EntRefToEntIndex(g_esPlayer[tank].g_iShield);
		if (bIsValidEntity(g_esPlayer[tank].g_iShield))
		{
			MT_HideEntity(g_esPlayer[tank].g_iShield, false);
			RemoveEntity(g_esPlayer[tank].g_iShield);
		}
	}

	g_esPlayer[tank].g_iShield = INVALID_ENT_REFERENCE;
}

static void vReset()
{
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (bIsValidClient(iPlayer, MT_CHECK_INGAME|MT_CHECK_INKICKQUEUE))
		{
			vReset2(iPlayer);
		}
	}
}

static void vReset2(int tank, bool revert = false)
{
	if (!revert)
	{
		g_esPlayer[tank].g_bActivated = false;
	}

	g_esPlayer[tank].g_flHealth = 0.0;
	g_esPlayer[tank].g_iCooldown = -1;
	g_esPlayer[tank].g_iDuration = -1;
	g_esPlayer[tank].g_iDuration2 = -1;
	g_esPlayer[tank].g_iShield = INVALID_ENT_REFERENCE;
	g_esPlayer[tank].g_iCount = 0;
}

static void vReset3(int tank)
{
	int iTime = GetTime();
	g_esPlayer[tank].g_iCooldown = (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0) ? (iTime + g_esCache[tank].g_iHumanCooldown) : -1;
	if (g_esPlayer[tank].g_iCooldown != -1 && g_esPlayer[tank].g_iCooldown > iTime)
	{
		MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman5", g_esPlayer[tank].g_iCooldown - iTime);
	}
}

static void vShield(int tank)
{
	if (!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags))
	{
		return;
	}

	static float flOrigin[3];
	GetClientAbsOrigin(tank, flOrigin);
	flOrigin[2] -= 120.0;

	SetEntityModel(g_esPlayer[tank].g_iShield, MODEL_SHIELD);

	DispatchKeyValueVector(g_esPlayer[tank].g_iShield, "origin", flOrigin);
	DispatchSpawn(g_esPlayer[tank].g_iShield);
	vSetEntityParent(g_esPlayer[tank].g_iShield, tank, true);

	SetEntityRenderMode(g_esPlayer[tank].g_iShield, RENDER_TRANSTEXTURE);
	SetEntityRenderColor(g_esPlayer[tank].g_iShield, g_esCache[tank].g_iShieldColor[0], g_esCache[tank].g_iShieldColor[1], g_esCache[tank].g_iShieldColor[2], g_esCache[tank].g_iShieldColor[3]);

	SetEntProp(g_esPlayer[tank].g_iShield, Prop_Send, "m_CollisionGroup", 1);

	MT_HideEntity(g_esPlayer[tank].g_iShield, true);
	g_esPlayer[tank].g_iShield = EntIndexToEntRef(g_esPlayer[tank].g_iShield);
}

static void vShieldAbility(int tank, bool shield)
{
	static int iTime;
	iTime = GetTime();

	switch (shield)
	{
		case true:
		{
			if ((!MT_HasAdminAccess(tank) && !bHasAdminAccess(tank, g_esAbility[g_esPlayer[tank].g_iTankType].g_iAccessFlags, g_esPlayer[tank].g_iAccessFlags)) || ((!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || g_esCache[tank].g_iHumanAbility != 1) && g_esPlayer[tank].g_iDuration2 != -1 && g_esPlayer[tank].g_iDuration2 > iTime))
			{
				return;
			}

			if (!MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) || (g_esPlayer[tank].g_iCount < g_esCache[tank].g_iHumanAmmo && g_esCache[tank].g_iHumanAmmo > 0))
			{
				if (GetRandomFloat(0.1, 100.0) <= g_esCache[tank].g_flShieldChance)
				{
					g_esPlayer[tank].g_iShield = CreateEntityByName("prop_dynamic");
					if (bIsValidEntity(g_esPlayer[tank].g_iShield))
					{
						g_esPlayer[tank].g_bActivated = true;
						g_esPlayer[tank].g_iDuration2 = -1;
						g_esPlayer[tank].g_flHealth = g_esCache[tank].g_flShieldHealth;

						vShield(tank);

						ExtinguishEntity(tank);

						if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
						{
							g_esPlayer[tank].g_iCount++;
							g_esPlayer[tank].g_iDuration = iTime + g_esPlayer[tank].g_iHumanDuration;

							MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman", g_esPlayer[tank].g_iCount, g_esCache[tank].g_iHumanAmmo);
						}

						if (g_esCache[tank].g_iShieldMessage == 1)
						{
							static char sTankName[33];
							MT_GetTankName(tank, sTankName);
							MT_PrintToChatAll("%s %t", MT_TAG2, "Shield", sTankName);
						}
					}
				}
				else if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
				{
					MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldHuman2");
				}
			}
			else if (MT_IsTankSupported(tank, MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
			{
				MT_PrintToChat(tank, "%s %t", MT_TAG3, "ShieldAmmo");
			}
		}
		case false:
		{
			g_esPlayer[tank].g_bActivated = false;
			g_esPlayer[tank].g_iDuration = -1;
			g_esPlayer[tank].g_flHealth = 0.0;

			vRemoveShield(tank);

			switch (MT_IsTankSupported(tank, MT_CHECK_INDEX|MT_CHECK_INGAME|MT_CHECK_ALIVE|MT_CHECK_INKICKQUEUE|MT_CHECK_FAKECLIENT) && g_esCache[tank].g_iHumanAbility == 1)
			{
				case true: vReset3(tank);
				case false: g_esPlayer[tank].g_iDuration2 = iTime + g_esCache[tank].g_iShieldDelay;
			}

			if (g_esCache[tank].g_iShieldMessage == 1)
			{
				static char sTankName[33];
				MT_GetTankName(tank, sTankName);
				MT_PrintToChatAll("%s %t", MT_TAG2, "Shield2", sTankName);
			}
		}
	}
}

public Action tTimerShieldThrow(Handle timer, DataPack pack)
{
	pack.Reset();

	static int iRock;
	iRock = EntRefToEntIndex(pack.ReadCell());
	if (!MT_IsCorePluginEnabled() || iRock == INVALID_ENT_REFERENCE || !bIsValidEntity(iRock))
	{
		return Plugin_Stop;
	}

	static int iTank, iType;
	iTank = GetClientOfUserId(pack.ReadCell());
	iType = pack.ReadCell();
	if (!MT_IsTankSupported(iTank) || (!MT_HasAdminAccess(iTank) && !bHasAdminAccess(iTank, g_esAbility[g_esPlayer[iTank].g_iTankType].g_iAccessFlags, g_esPlayer[iTank].g_iAccessFlags)) || !MT_IsTypeEnabled(g_esPlayer[iTank].g_iTankType) || !bIsCloneAllowed(iTank) || iType != g_esPlayer[iTank].g_iTankType || g_esCache[iTank].g_iShieldAbility == 0 || !g_esPlayer[iTank].g_bActivated)
	{
		return Plugin_Stop;
	}

	if (g_esCache[iTank].g_iShieldType != 1 && g_esCache[iTank].g_iShieldType != 2)
	{
		return Plugin_Stop;
	}

	static float flVelocity[3];
	GetEntPropVector(iRock, Prop_Data, "m_vecVelocity", flVelocity);

	static float flVector;
	flVector = GetVectorLength(flVelocity);
	if (flVector > 500.0)
	{
		static int iThrowable;
		iThrowable = CreateEntityByName("prop_physics");
		if (bIsValidEntity(iThrowable))
		{
			switch (g_esCache[iTank].g_iShieldType)
			{
				case 1: SetEntityModel(iThrowable, MODEL_PROPANETANK);
				case 2: SetEntityModel(iThrowable, MODEL_GASCAN);
			}

			static float flPos[3];
			GetEntPropVector(iRock, Prop_Send, "m_vecOrigin", flPos);
			RemoveEntity(iRock);

			NormalizeVector(flVelocity, flVelocity);
			ScaleVector(flVelocity, g_cvMTTankThrowForce.FloatValue * 1.4);

			DispatchSpawn(iThrowable);
			TeleportEntity(iThrowable, flPos, NULL_VECTOR, flVelocity);
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}