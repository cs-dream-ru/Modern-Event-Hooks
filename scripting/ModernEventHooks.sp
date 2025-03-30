#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <sdktools_engine>
#include <sdktools_functions>

enum GrenadeType
{
	He, 
	Flash, 
	Smoke
};

bool
	g_bAssister[MAXPLAYERS + 1][MAXPLAYERS + 1], 
	g_bFlashed[MAXPLAYERS + 1][MAXPLAYERS + 1], 
	g_bNotFreezepanel;

int
	g_iDmg[MAXPLAYERS + 1][MAXPLAYERS + 1], 
	g_iCountObstacles[MAXPLAYERS + 1], 
	g_iFlashOwner, 
	g_iHits[MAXPLAYERS + 1][MAXPLAYERS + 1], 
	g_iNearVictim, 
	g_iNearEnt[GrenadeType], 
	g_iMaxClients, 
	m_flFlashDuration, 
	m_hThrower, 
	m_vecOrigin;

public Plugin myinfo = 
{
	name = "[CS:S] Modern Event Hooks", 
	version = "1.1.0", 
	author = "Wend4r & who", 
	url = "Discord: Wend4r#0001 | VK: vk.com/wend4r"
}

public APLRes AskPluginLoad2()
{
	EngineVersion Engine = GetEngineVersion();
	
	if (Engine != Engine_CSS && Engine != Engine_SourceSDK2006)
	{
		SetFailState("This plugin works only on CS:S OB and CS:S v34");
	}
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("hegrenade_detonate", Event_GrenadeDetonate, EventHookMode_Pre);
	HookEvent("flashbang_detonate", Event_GrenadeDetonate, EventHookMode_Pre);
	HookEvent("smokegrenade_detonate", Event_GrenadeDetonate, EventHookMode_Pre);
	HookEvent("player_blind", Event_Blind, EventHookMode_Pre);
	HookEvent("player_hurt", Event_Hurt);
	
	HookEvent("bullet_impact", Event_Bullet);
	HookEvent("weapon_fire", Event_Bullet);
	
	HookEvent("player_death", Event_Death, EventHookMode_Pre);
	
	// For CS:S v34
	if (!HookEventEx("show_freezepanel", Event_FreezePanel, EventHookMode_Pre))
	{
		g_bNotFreezepanel = true;
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	m_flFlashDuration = FindSendPropInfo("CCSPlayer", "m_flFlashDuration");
	m_hThrower = FindSendPropInfo("CBaseGrenade", "m_hThrower");
	m_vecOrigin = FindSendPropInfo("CBaseEntity", "m_vecOrigin");
	
	g_iMaxClients = GetMaxHumanPlayers() + 1;
}

public void OnEntityCreated(int iEnt, const char[] sClassname)
{
	if (StrContains(sClassname, "_projectile", false) != -1)
	{
		switch (sClassname[0])
		{
			case 'h':
			{
				g_iNearEnt[He] = iEnt;
			}
			
			case 'f':
			{
				g_iNearEnt[Flash] = iEnt;
				
				int iOwner = GetEntDataEnt2(iEnt, m_hThrower);
				
				g_iFlashOwner = iOwner == -1 ? 0 : IsClientInGame(iOwner) ? iOwner : 0;
			}
			
			case 's':
			{
				g_iNearEnt[Smoke] = iEnt;
			}
		}
	}
}

public void OnEntityDestroyed(int iEnt)
{
	if (IsValidEntity(iEnt))
	{
		static char sClassname[32];
		GetEntityClassname(iEnt, sClassname, sizeof(sClassname));
		
		if (StrEqual(sClassname, "smokegrenade_projectile"))
		{
			Event event = CreateEvent("smokegrenade_expired", true);
			
			if (event)
			{
				int iOwner = GetEntDataEnt2(iEnt, m_hThrower);
				
				event.SetInt("userid", iOwner == -1 ? 0 : GetClientUserId(iOwner));
				event.SetInt("entityid", iEnt);
				
				float vecSmoke[3];
				GetEntDataVector(iEnt, m_vecOrigin, vecSmoke);
				
				event.SetFloat("x", vecSmoke[0]);
				event.SetFloat("y", vecSmoke[1]);
				event.SetFloat("z", vecSmoke[2]);
				
				event.Fire();
			}
		}
	}
}

public Action Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast)
{
	GrenadeType Type;

	switch (name[0])
	{
		case 'h':	Type = He;
		case 'f':	Type = Flash;
		default:	Type = Smoke;
	}

	event.SetInt("entityid", g_iNearEnt[Type]);

	return Plugin_Changed;
}

public Action Event_Blind(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	
	g_bFlashed[iClient][g_iFlashOwner] = true;
	
	event.SetInt("attacker", g_iFlashOwner ? GetClientUserId(g_iFlashOwner) : 0);
	event.SetInt("entityid", g_iNearEnt[Flash]);
	
	event.SetInt("flashoffset", m_flFlashDuration);
	event.SetFloat("blind_duration", GetEntDataFloat(iClient, m_flFlashDuration));
	
	return Plugin_Changed;
}

public void Event_Hurt(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if ((g_iDmg[iClient][iAttacker] += event.GetInt("dmg_health")) >= 40)
	{
		if (!g_bAssister[iClient][iAttacker])
		{
			g_bAssister[iClient][iAttacker] = true;
		}
	}
	
	g_iHits[iClient][iAttacker]++;
}

public void Event_Bullet(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (name[0] == 'b')
	{
		g_iCountObstacles[client]++;
	}
	else
	{
		g_iCountObstacles[client] = 0;
	}
}

public Action Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = (g_iNearVictim = GetClientOfUserId(event.GetInt("userid"))); 
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	int iAssister;
	
	if (iClient && iAttacker && iClient != iAttacker)
	{
		for (int i = 1; i != g_iMaxClients; i++)
		{
			if (g_bAssister[iClient][i])
			{
				if (i != iAttacker)
				{
					iAssister = i;
					break;
				}
			}
		}
		
		static char sWeapon[8];
		event.GetString("weapon", sWeapon, sizeof(sWeapon));
		
		if (g_iCountObstacles[iAttacker] > 1)
		{
			if (!StrEqual(sWeapon, "m3") && !StrEqual(sWeapon, "xm1014") && !StrEqual(sWeapon, "knife"))
			{
				event.SetInt("penetrated", g_iCountObstacles[iAttacker]);
			}
		}
		
		if (StrEqual(sWeapon, "awp") || StrEqual(sWeapon, "scout") || StrEqual(sWeapon, "sg550") || StrEqual(sWeapon, "g3sg1"))
		{
			static bool noscope;
			
			int wpn = GetEntPropEnt(iAttacker, Prop_Send, "m_hActiveWeapon");
			
			noscope = wpn != -1 && !GetEntProp(wpn, Prop_Send, "m_weaponMode") ? true:false;
			
			event.SetBool("noscope", noscope);
		}
	}
	
	if (g_bNotFreezepanel)
	{
		Event event2 = CreateEvent("show_freezepanel", true);
		
		// I love you, CS:S v34
		if (event2)
		{
			event2.SetInt("killer", iAttacker);
			
			Event_FreezePanel(event2, "show_freezepanel", false);
			
			event2.Fire();
		}
	}
	
	if (iAssister)
	{
		if (IsClientInGame(iAssister))
		{
			event.SetInt("assister", GetClientUserId(iAssister));
			event.SetBool("assistedflash", g_bFlashed[iClient][iAssister]);
		}
	}
	
	return Plugin_Changed;
}

public Action Event_FreezePanel(Event event, const char[] name, bool dontBroadcast)
{
	int iAttacker = event.GetInt("killer");
	
	event.SetInt("victim", g_iNearVictim);
	event.SetInt("hits_taken", g_iHits[iAttacker][g_iNearVictim]);
	event.SetInt("damage_taken", g_iDmg[iAttacker][g_iNearVictim]);
	event.SetInt("hits_given", g_iHits[g_iNearVictim][iAttacker]);
	event.SetInt("damage_given", g_iDmg[g_iNearVictim][iAttacker]);
	
	return Plugin_Changed;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	for (int i = 1; i != g_iMaxClients; i++)
	{
		g_iDmg[client][i] = 0;
		g_iHits[client][i] = 0;
		g_bAssister[client][i] = false;
		g_bFlashed[client][i] = false;
	}
} 