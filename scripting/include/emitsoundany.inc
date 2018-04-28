/**
 * vim: set ts=4 :
 * =============================================================================
 * EmitSoundAny
 * Play sounds in a cross-game friendly way CS:GO and DOTA2 friendly way.
 *
 * EmitSoundAny (C)2014 AlliedModders and Powerlord (Ross Bemrose)
 * SourceMod (C)2004-2007 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: 1.0.3
 */
#if defined _emitsoundany_included
 #endinput
#endif
#define _emitsoundany_included

#include <sdktools>

static bool:g_bCheckedEngine = false;
static bool:g_bNeedsFakePrecache = false;

stock static EmitSoundCheckEngineVersion()
{
	if(g_bCheckedEngine)
	{
		return;
	}

	new EngineVersion:engVersion = GetEngineVersion();
	
	if(engVersion == Engine_CSGO || engVersion == Engine_DOTA)
	{
		g_bNeedsFakePrecache = true;
	}
	g_bCheckedEngine = true;
}

stock static bool:FakePrecacheSoundEx(const String:sPath[])
{
	decl String:sPathStar[PLATFORM_MAX_PATH];
	Format(sPathStar, sizeof(sPathStar), "*%s", sPath);
	
	AddToStringTable(FindStringTable("soundprecache"), sPathStar);
	return true;
}

stock bool:PrecacheSoundAny(const String:sPath[], bool:bPreload=false)
{
	EmitSoundCheckEngineVersion();
	
	if(g_bNeedsFakePrecache)
	{
		return FakePrecacheSoundEx(sPath);
	}
	else
	{
		return PrecacheSound(sPath, bPreload);
	}
}

stock EmitSoundAny(const clients[], numClients, const String:sSample[], iEntity = SOUND_FROM_PLAYER, channel = SNDCHAN_AUTO, level = SNDLEVEL_NORMAL, flags = SND_NOFLAGS, Float:fVolume = SNDVOL_NORMAL, pitch = SNDPITCH_NORMAL, iSpeakerEntity = -1, const Float:fOrigin[3] = NULL_VECTOR, const Float:fDir[3] = NULL_VECTOR, bool:bUpdatePos = true, Float:fSoundTime = 0.0)
{
	EmitSoundCheckEngineVersion();

	decl String:sSound[PLATFORM_MAX_PATH];
	
	if(g_bNeedsFakePrecache)
	{
		Format(sSound, sizeof(sSound), "*%s", sSample);
	}
	else
	{
		strcopy(sSound, sizeof(sSound), sSample);
	}
	
	EmitSound(clients, numClients, sSound, iEntity, channel, level, flags, fVolume, pitch, iSpeakerEntity, fOrigin, fDir, bUpdatePos, fSoundTime);	
}

stock EmitSoundToClientAny(client, const String:sSample[], iEntity = SOUND_FROM_PLAYER, channel = SNDCHAN_AUTO, level = SNDLEVEL_NORMAL, flags = SND_NOFLAGS, Float:fVolume = SNDVOL_NORMAL, pitch = SNDPITCH_NORMAL, iSpeakerEntity = -1, const Float:fOrigin[3] = NULL_VECTOR, const Float:fDir[3] = NULL_VECTOR, bool:bUpdatePos = true, Float:fSoundTime = 0.0)
{
	new a_iClients[1];
	a_iClients[0] = client;
	/* Save some work for SDKTools and remove SOUND_FROM_PLAYER references */
	iEntity = (iEntity == SOUND_FROM_PLAYER) ? client : iEntity;
	EmitSoundAny(a_iClients, 1, sSample, iEntity, channel, level, flags, fVolume, pitch, iSpeakerEntity, fOrigin, fDir, bUpdatePos, fSoundTime);
}

stock EmitSoundToAllAny(const String:sSample[], iEntity = SOUND_FROM_PLAYER, channel = SNDCHAN_AUTO, level = SNDLEVEL_NORMAL, flags = SND_NOFLAGS, Float:fVolume = SNDVOL_NORMAL, pitch = SNDPITCH_NORMAL, iSpeakerEntity = -1, const Float:fOrigin[3] = NULL_VECTOR, const Float:fDir[3] = NULL_VECTOR, bool:bUpdatePos = true, Float:fSoundTime = 0.0)
{
	new a_iClients[MaxClients];
	new iTotal = 0;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			a_iClients[iTotal++] = i;
		}
	}
	
	if(!iTotal)
	{
		return;
	}
	
	EmitSoundAny(a_iClients, iTotal, sSample, iEntity, channel, level, flags, fVolume, pitch, iSpeakerEntity, fOrigin, fDir, bUpdatePos, fSoundTime);
}

stock EmitAmbientSoundAny(const String:sSample[], const Float:fPos[3], iEntity = SOUND_FROM_WORLD, level = SNDLEVEL_NORMAL, flags = SND_NOFLAGS, Float:fVol = SNDVOL_NORMAL, pitch = SNDPITCH_NORMAL, Float:fDelay = 0.0)
{
	EmitSoundCheckEngineVersion();
	
	decl String:sSound[PLATFORM_MAX_PATH];
	
	if(g_bNeedsFakePrecache)
	{
		Format(sSound, sizeof(sSound), "*%s", sSample);
	}
	else
	{
		strcopy(sSound, sizeof(sSound), sSample);
	}
	
	EmitAmbientSound(sSound, fPos, iEntity, level, flags, fVol, pitch, fDelay);
}

stock StopSoundAny(iEntity, channel, const String:sName[])
{
	EmitSoundCheckEngineVersion();
	
	decl String:sSound[PLATFORM_MAX_PATH];
	
	if(g_bNeedsFakePrecache)
	{
		Format(sSound, sizeof(sSound), "*%s", sName);
	}
	else
	{
		strcopy(sSound, sizeof(sSound), sName);
	}
	
	StopSound(iEntity, channel, sSound);
}