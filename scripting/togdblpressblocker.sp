/*
	RemoveIgnoredButton has note: //NEED TO ADD TOLERANCE FOR BUTTONS HERE.
	
	currently, checks still need to be made to stop enabling maps or auto-ignore if the cvar is turned off perm. Needs checks in GetLists and in admin menu
*/

#pragma semicolon 1
#pragma dynamic 131072 //increase stack space to from 4 kB to 131072 cells (or 512KB, a cell is 4 bytes)

#define PLUGIN_VERSION "3.0"
#define CSGO_RED " \x07"
#define CSS_RED "\x07FF0000"
#define LoopValidPlayers(%1)						for(int %1 = 1;%1 <= MaxClients; %1++)		if(IsValidClient(%1))
#define LoopValidPlayers_Bots(%1)				for(int %1 = 1;%1 <= MaxClients; %1++)		if(IsValidClient(%1, true))
#define LoopValidPlayers_Bots_Dead(%1,%2,%3)		for(int %1 = 1;%1 <= MaxClients; %1++)		if(IsValidClient(%1, %2, %3))
#define SOUND_BLIP "buttons/blip1.wav"
#define TAG "[TDPB] "

#include <sourcemod>
#include <autoexecconfig>
#include <sdktools>
#include <adminmenu>
#include <emitsoundany>

#pragma newdecls required

Handle g_hTopMenu = INVALID_HANDLE;
bool g_bCSGO = false;

//cvars
ConVar g_hEnabled = null;
ConVar g_hAutoIgnore = null;
ConVar g_hAdminFlag = null;
char g_sAdminFlag[30];
ConVar g_hDefaultRGB_Pre = null;
int g_iRGB_Pre_R, g_iRGB_Pre_G, g_iRGB_Pre_B;
ConVar g_hDefaultRGB_Post = null;
int g_iRGB_Post_R, g_iRGB_Post_G, g_iRGB_Post_B;
ConVar g_hTolerance = null;

Handle g_hLockedButtons = INVALID_HANDLE;				//list of Entity refs for currently locked buttons
Handle g_hIgnoredButtons = INVALID_HANDLE;				//list of Hammer IDs for ignored buttons
Handle g_hIgnoredButtonsOrigins = INVALID_HANDLE;		//list of button coordinates for ignored buttons

int g_iTotalIgnored = 0;
int g_iTotalActive = 0;

//BEACON
int g_iBeamSprite 		= -1;
int g_iHaloSprite 		= -1;
int ga_iRedColor[4]		= {255, 75, 75, 255};
int ga_iOrangeColor[4]	= {255, 128, 0, 255};
int ga_iGreenColor[4]		= {75, 255, 75, 255};
int ga_iBlueColor[4]		= {75, 75, 255, 255};
int ga_iGreyColor[4]		= {128, 128, 128, 255};

public Plugin myinfo =
{
	name = "TOG Double Press Blocker",
	author = "That One Guy",
	description = "Blocks pressing buttons multiple times, allows admins to add buttons to an ignore list, see button info, find buttons, and more.",
	version = PLUGIN_VERSION,
	url = "http://www.togcoding.com"
}

public void OnPluginStart()
{
	char sGameFolder[32], sDescription[64];
	GetGameDescription(sDescription, sizeof(sDescription), true);
	GetGameFolderName(sGameFolder, sizeof(sGameFolder));
	if((StrContains(sGameFolder, "csgo", false) != -1) || (StrContains(sDescription, "Counter-Strike: Global Offensive", false) != -1))
	{
		g_bCSGO = true;
	}
	
	AutoExecConfig_SetFile("togdblpressblocker");
	AutoExecConfig_CreateConVar("tdpb_version", PLUGIN_VERSION, "TOG Double Press Blocker: Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_hEnabled = AutoExecConfig_CreateConVar("tdpb_enable", "1", "Enable plugin by default on each map? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
	
	g_hAutoIgnore = AutoExecConfig_CreateConVar("tdpb_auto_ignore", "0", "Automatically add buttons to the ignore list if the map triggers them and the feature is not disabled for the current map (0 = Disabled, 1 = Enabled).", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hAdminFlag = AutoExecConfig_CreateConVar("tdpb_adminflag", "g", "Admin Flag to check for.");
	g_hAdminFlag.AddChangeHook(OnCVarChange);
	g_hAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
	
	g_hDefaultRGB_Pre = AutoExecConfig_CreateConVar("tdpb_preglow_pre", "0 255 0", "RGB value to use as default glow for unpressed butotns (0-255, with spaces between).");
	g_hDefaultRGB_Pre.AddChangeHook(OnCVarChange);
	char sBufferPre[20];
	char a_sTempArrayPre[3][5];
	g_hDefaultRGB_Pre.GetString(sBufferPre, sizeof(sBufferPre));
	ExplodeString(sBufferPre, " ", a_sTempArrayPre, sizeof(a_sTempArrayPre), sizeof(a_sTempArrayPre[]));
	g_iRGB_Pre_R = StringToInt(a_sTempArrayPre[0]);
	g_iRGB_Pre_G = StringToInt(a_sTempArrayPre[1]);
	g_iRGB_Pre_B = StringToInt(a_sTempArrayPre[2]);
	
	g_hDefaultRGB_Post = AutoExecConfig_CreateConVar("tdpb_glow_post", "255 0 0", "RGB value to use as default glow for pressed butotns (0-255, with spaces between).");
	g_hDefaultRGB_Post.AddChangeHook(OnCVarChange);
	char sBufferPost[20];
	char a_sTempArrayPost[3][5];
	g_hDefaultRGB_Post.GetString(sBufferPost, sizeof(sBufferPost));
	ExplodeString(sBufferPost, " ", a_sTempArrayPost, sizeof(a_sTempArrayPost), sizeof(a_sTempArrayPost[]));
	g_iRGB_Post_R = StringToInt(a_sTempArrayPost[0]);
	g_iRGB_Post_G = StringToInt(a_sTempArrayPost[1]);
	g_iRGB_Post_B = StringToInt(a_sTempArrayPost[2]);
	
	g_hTolerance = AutoExecConfig_CreateConVar("tdpb_origin_tolerance", "30", "Distance tolerance in button coordinates check (used only if Hammer ID = 0 (old maps only)).", FCVAR_NONE, true, 0.0);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	RegConsoleCmd("sm_buttons", Cmd_ListButtons, "Opens button list menu.");
	RegConsoleCmd("sm_resetbuttons", Cmd_ResetButtons, "Resets buttons locked by plugin this round.");
	RegConsoleCmd("sm_ident", Cmd_ID, "Returns information about the entity in the client's crosshairs.");
	RegConsoleCmd("sm_preglow", Cmd_PreGlow, "Sets glow color (RGB) of buttons before they are pressed.");
	RegConsoleCmd("sm_postglow", Cmd_PostGlow, "Sets glow color (RGB) of buttons after they are pressed.");
	RegConsoleCmd("sm_ignore", Cmd_IgnoreButton, "Tells plugin to not lock a specific button after it is pressed.");
	RegConsoleCmd("sm_tolerance", Cmd_Tolerance, "Sets tolerance override for the map (only important on maps without Hammer IDs for buttons).");
	RegConsoleCmd("sm_removeautoignore", Cmd_RemoveAutoIgnore, "Removes auto-ignore function for the given map (if applicable).");
	RegConsoleCmd("sm_enableautoignore", Cmd_EnableAutoIgnore, "Re-enables auto-ignore function for the given map (if applicable).");

	g_hLockedButtons = CreateArray(32);
	g_hIgnoredButtons = CreateArray(32);
	g_hIgnoredButtonsOrigins = CreateArray(4);
	
	HookEntityOutput("func_button", "OnIn", FuncButtonOutput);
	HookEntityOutput("func_rot_button", "OnIn", FuncButtonOutput);
	
	HookEvent("round_start", OnRoundStart, EventHookMode_Post);
	
	Handle hTopMenu;
	if(LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(hTopMenu);
	}
}

public void OnCVarChange(ConVar hCVar, const char[] sOldValue, const char[] sNewValue)
{
	if(hCVar == g_hAdminFlag)
	{
		g_hAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
	}
	else if(hCVar == g_hDefaultRGB_Pre)
	{
		char sBufferPre[20];
		char a_sTempArrayPre[3][5];
		g_hDefaultRGB_Pre.GetString(sBufferPre, sizeof(sBufferPre));
		ExplodeString(sBufferPre, " ", a_sTempArrayPre, sizeof(a_sTempArrayPre), sizeof(a_sTempArrayPre[]));
		g_iRGB_Pre_R = StringToInt(a_sTempArrayPre[0]);
		g_iRGB_Pre_G = StringToInt(a_sTempArrayPre[1]);
		g_iRGB_Pre_B = StringToInt(a_sTempArrayPre[2]);
		GetLists();
		SetButtonGlows();
	}
	else if(hCVar == g_hDefaultRGB_Post)
	{
		char sBufferPost[20];
		char a_sTempArrayPost[3][5];
		g_hDefaultRGB_Post.GetString(sBufferPost, sizeof(sBufferPost));
		ExplodeString(sBufferPost, " ", a_sTempArrayPost, sizeof(a_sTempArrayPost), sizeof(a_sTempArrayPost[]));
		g_iRGB_Post_R = StringToInt(a_sTempArrayPost[0]);
		g_iRGB_Post_G = StringToInt(a_sTempArrayPost[1]);
		g_iRGB_Post_B = StringToInt(a_sTempArrayPost[2]);
		GetLists();
		SetButtonGlows();
	}
}

public void OnLibraryRemoved(const char[] sName)
{
	if(StrEqual(sName, "adminmenu"))
	{
		g_hTopMenu = INVALID_HANDLE;
	}
}

void LockButton(int iButtonEnt)
{
	SetEntProp(iButtonEnt, Prop_Data, "m_bLocked", 1, 1);
}

void UnlockButton(int iButtonEnt)
{
	SetEntProp(iButtonEnt, Prop_Data, "m_bLocked", 0, 1);
}

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
	PrecacheSoundAny(SOUND_BLIP, true);

	ClearArray(g_hLockedButtons);
	ClearArray(g_hIgnoredButtons);
	ClearArray(g_hIgnoredButtonsOrigins);
	GetLists();
	ResetButtons();
	SetButtonGlows();
}

public void GetLists()
{
	char sMap[128];
	GetCurrentMap(sMap, sizeof(sMap));
	
	g_iTotalIgnored = 0;
	g_iTotalActive = 0;

	ClearArray(g_hIgnoredButtons);
	ClearArray(g_hIgnoredButtonsOrigins);

	char sFile[PLATFORM_MAX_PATH], sBuffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/togdblpressblocker/%s.cfg", sMap);
	if(!FileExists(sFile))
	{
		CreateTimer(20.0, TimerCallback_NewMapAdminMsg, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	Handle hFile = OpenFile(sFile, "r");
	
	if(hFile != INVALID_HANDLE)
	{
		while(ReadFileLine(hFile, sBuffer, sizeof(sBuffer)))
		{
			TrimString(sBuffer);		//remove spaces and tabs at both ends of string
			if((StrContains(sBuffer, "//") == -1) && (!StrEqual(sBuffer, "")))		//filter out comments and blank lines
			{
				if(StrEqual(sBuffer, "MAP DISABLED"))
				{
					g_hEnabled.BoolValue = false;
				}
				else if(StrContains(sBuffer, "PREGLOW") != -1)
				{
					char a_sTempArrayPre[4][10];
					ExplodeString(sBuffer, " ", a_sTempArrayPre, sizeof(a_sTempArrayPre), sizeof(a_sTempArrayPre[]));
					g_iRGB_Pre_R = StringToInt(a_sTempArrayPre[1]);
					g_iRGB_Pre_G = StringToInt(a_sTempArrayPre[2]);
					g_iRGB_Pre_B = StringToInt(a_sTempArrayPre[3]);
				}
				else if(StrContains(sBuffer, "POSTGLOW") != -1)
				{
					char a_sTempArrayPost[4][10];
					ExplodeString(sBuffer, " ", a_sTempArrayPost, sizeof(a_sTempArrayPost), sizeof(a_sTempArrayPost[]));
					g_iRGB_Post_R = StringToInt(a_sTempArrayPost[1]);
					g_iRGB_Post_G = StringToInt(a_sTempArrayPost[2]);
					g_iRGB_Post_B = StringToInt(a_sTempArrayPost[3]);
				}
				else if(StrContains(sBuffer, "TOLERANCE") != -1)
				{
					char sTempArrayTol[2][5];
					ExplodeString(sBuffer, " ", sTempArrayTol, sizeof(sTempArrayTol), sizeof(sTempArrayTol[]));
					g_hTolerance.IntValue = StringToInt(sTempArrayTol[1]);
				}
				else if(StrContains(sBuffer, "NOAUTOIGNORE") != -1)
				{
					g_hAutoIgnore.BoolValue = false;
				}
				else if(StrContains(sBuffer, "ORIGIN") != -1)
				{
					char sTempArrayOrigin[4][10];
					ExplodeString(sBuffer, " ", sTempArrayOrigin, sizeof(sTempArrayOrigin), sizeof(sTempArrayOrigin[]));

					int a_iEntPosFromFile[3];
					a_iEntPosFromFile[0] = StringToInt(sTempArrayOrigin[1]);
					a_iEntPosFromFile[1] = StringToInt(sTempArrayOrigin[2]);
					a_iEntPosFromFile[2] = StringToInt(sTempArrayOrigin[3]);
					PushArrayArray(g_hIgnoredButtonsOrigins, a_iEntPosFromFile);	//slot j?
				}
				else
				{
					PushArrayCell(g_hIgnoredButtons, StringToInt(sBuffer));
				}
			}
		}
	}
	
	int iEntCnt = GetEntityCount();
	for(int i = 2; i <= iEntCnt; i++)	//start at 2, since entID 1 is the map itself
	{
		if(IsValidEntity(i))
		{
			// Get classname from entity
			char sClassName[128];
			GetEntityClassname(i, sClassName, sizeof(sClassName));
			if(!StrEqual(sClassName,"func_button",false) && !StrEqual(sClassName,"func_rot_button",false))
			{
				continue;
			}
			else
			{
				int iHammerID = GetEntProp(i, Prop_Data, "m_iHammerID");
				int iOrigin = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
				float fEntityPos[3];
				GetEntDataVector(i, iOrigin, fEntityPos);
				int a_iEntityPos[3];
				a_iEntityPos[0] = RoundFloat(fEntityPos[0]);
				a_iEntityPos[1] = RoundFloat(fEntityPos[1]);
				a_iEntityPos[2] = RoundFloat(fEntityPos[2]);
				
				if((FindValueInArray(g_hIgnoredButtons, iHammerID) == -1) && (SearchForArrayInIgnoredOrigins(a_iEntityPos) == -1))
				{
					g_iTotalActive++;
				}
				else
				{
					g_iTotalIgnored++;
				}
			}
		}
	}
	
	if(hFile != INVALID_HANDLE)
	{
		CloseHandle(hFile);
	}
}

int SearchForArrayInIgnoredOrigins(int[] a_iEntityPos)
{
	for(int i = 0; i < GetArraySize(g_hIgnoredButtonsOrigins); i++)
	{
		int a_iEntityPosFromFile[3];
		GetArrayArray(g_hIgnoredButtonsOrigins, i, a_iEntityPosFromFile);
		
		if((RoundFloat(FloatAbs(float(a_iEntityPosFromFile[0] - a_iEntityPos[0]))) < g_hTolerance.IntValue) && (RoundFloat(FloatAbs(float(a_iEntityPosFromFile[1] - a_iEntityPos[1]))) < g_hTolerance.IntValue) && (RoundFloat(FloatAbs(float(a_iEntityPosFromFile[2] - a_iEntityPos[2]))) < g_hTolerance.IntValue))
		{
			return i;
		}
	}
	return -1;
}

void VerifyMap(int client)
{
	char sMap[128];
	GetCurrentMap(sMap, sizeof(sMap));
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "configs/togdblpressblocker/%s.cfg", sMap);
	CreateFile(sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%L has verified map '%s'", client, sMap);
	Log("togdblpressblocker.log", sBuffer);
}

public Action TimerCallback_NewMapAdminMsg(Handle timer)
{
	MsgAdmins_Chat(g_sAdminFlag, "%s%sBUTTON CONFIGS HAVE NOT BEEN SET FOR THIS MAP. PLEASE ADD ANY 'SECRET' OR DOOR BUTTONS TO THE IGNORE LIST!", g_bCSGO? CSGO_RED : CSS_RED, TAG);
	return Plugin_Continue;
}

void IgnoreButton(int client, int iHammerID, int[] a_iEntityPos)
{
	char sMap[128], sPath[256], sBuffer[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sPath, sizeof(sPath), "configs/togdblpressblocker/%s.cfg", sMap);
	
	if(iHammerID != 0)
	{
		IntToString(iHammerID, sBuffer, sizeof(sBuffer));
		RemoveFileLine_Equal(sPath, sBuffer);
		WriteLineToFile(sPath, sBuffer);
		if(client == 0)
		{
			MsgAdmins_Chat(g_sAdminFlag, "%s%sBUTTON WITH HAMMER ID '%i' WAS AUTOMATICALLY ADDED TO IGNORE LIST DUE TO BEING TRIGGERED BY SERVER!", g_bCSGO? CSGO_RED : CSS_RED, TAG, iHammerID);
			Format(sBuffer, sizeof(sBuffer), "BUTTON WITH HAMMER ID '%i' WAS AUTOMATICALLY ADDED TO IGNORE LIST FOR MAP '%s' DUE TO BEING TRIGGERED BY SERVER!", iHammerID, sMap);
			Log("togdblpressblocker.log", sBuffer);
		}
		else
		{
			PrintToChat(client, " \x03%sHammerID %i is now added to ignore list for this map.", TAG, iHammerID);
			Format(sBuffer, sizeof(sBuffer), "HammerID %i is now added to ignore list for map '%s' by admin %L.", iHammerID, sMap, client);
			Log("togdblpressblocker.log", sBuffer);
		}
	}
	else
	{
		Format(sBuffer, sizeof(sBuffer), "ORIGIN %i %i %i", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
		RemoveFileLine_Equal(sPath, sBuffer);
		WriteLineToFile(sPath, sBuffer);
		if(client == 0)
		{
			MsgAdmins_Chat(g_sAdminFlag, "%s%sBUTTON AT COORDINATES: %i %i %i WAS AUTOMATICALLY ADDED TO IGNORE LIST DUE TO BEING TRIGGERED BY SERVER!", g_bCSGO? CSGO_RED : CSS_RED, TAG, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
			Format(sBuffer, sizeof(sBuffer), "BUTTON AT COORDINATES: %i %i %i WAS AUTOMATICALLY ADDED TO IGNORE LIST FOR MAP '%s' DUE TO BEING TRIGGERED BY SERVER!", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2], sMap);
			Log("togdblpressblocker.log", sBuffer);
		}
		else
		{
			PrintToChat(client, " \x03%sButton at coordinates: %i %i %i is now added to ignore list for this map.", TAG, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
			Format(sBuffer, sizeof(sBuffer), "Button at coordinates: %i %i %i is now added to ignore list for map '%s' by admin %L.", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2], sMap, client);
			Log("togdblpressblocker.log", sBuffer);
		}
	}
	
	GetLists();	//rebuild lists
	SetButtonGlows();
}

void RemoveIgnoredButton(int client, int iHammerID, int[] a_iEntityPos)
{
	char sMap[128], sFile[256], sBuffer[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sFile, sizeof(sFile), "configs/togdblpressblocker/%s.cfg", sMap);
	
	if(iHammerID != 0)
	{
		IntToString(iHammerID, sBuffer, sizeof(sBuffer));
		RemoveFileLine_Equal(sFile, sBuffer);
		PrintToChat(client, " \x03%sHammerID %i is now removed from the ignore list for this map.", TAG, iHammerID);
		Format(sBuffer, sizeof(sBuffer), "HammerID %i was removed from ignore list for map '%s' by admin %L.", iHammerID, sMap, client);
		Log("togdblpressblocker.log", sBuffer);
	}
	else
	{
		//NEED TO ADD TOLERANCE FOR BUTTONS HERE.
		Format(sBuffer, sizeof(sBuffer), "ORIGIN %i %i %i", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
		RemoveFileLine_Equal(sFile, sBuffer);
		PrintToChat(client, " \x03%sButton at coordinates: %i %i %i is now removed from the ignore list for this map.", TAG, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
		Format(sBuffer, sizeof(sBuffer), "Button at coordinates: %i %i %i was removed from ignore list for map '%s' by admin %L.", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2], sMap, client);
		Log("togdblpressblocker.log", sBuffer);
	}
	
	GetLists();	//rebuild lists
	SetButtonGlows();
}

void TriggerButton(int client, int iEntID, int[] a_iEntityPos)
{
	if(IsValidEntity(iEntID))
	{
		// Get classname from entity
		char sEdictName[128];
		GetEdictClassname(iEntID, sEdictName, sizeof(sEdictName));

		// Check if classname is simalar to the trigger command
		if((StrContains(sEdictName, "func_button", false) != -1) || (StrContains(sEdictName, "func_rot_button", false) != -1))
		{
			int iHammerID = GetEntProp(iEntID, Prop_Data, "m_iHammerID");

			char sButtonName[MAX_NAME_LENGTH];
			sButtonName[0] = '\0';
			GetEntPropString(iEntID, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
			if(strcmp(sButtonName, "") == 0)
			{
				sButtonName = "<no name>";
			}
			AcceptEntityInput(iEntID, "Press", client, iEntID);
			PrintToChatAll("%s%s%N has forced button '%s' to trigger.", g_bCSGO? CSGO_RED : CSS_RED, TAG, client, sButtonName);
			PrintToChatAll("%sHID: %i, EID: %i, X: %i, Y: %i, Z: %i", g_bCSGO? CSGO_RED : CSS_RED, iHammerID, iEntID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
		}
	}
	return;
}

void DisableMap(int client)
{
	g_hEnabled.BoolValue = false;
	char sMap[128], sBuffer[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sBuffer, sizeof(sBuffer), "configs/togdblpressblocker/%s.cfg", sMap);
	
	WriteLineToFile(sBuffer, "MAP DISABLED");
	
	Format(sBuffer, sizeof(sBuffer), "Map '%s' was disabled by admin %L.", sMap, client);
	Log("togdblpressblocker.log", sBuffer);
	
	ResetButtons();
	SetButtonGlows();
}

void EnableMap(int client)
{
	g_hEnabled.BoolValue = true;
	
	char sMap[128], sBuffer[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sBuffer, sizeof(sBuffer), "configs/togdblpressblocker/%s.cfg", sMap);
	
	RemoveFileLine_Equal(sBuffer, "MAP DISABLED");

	Format(sBuffer, sizeof(sBuffer), "Map '%s' was enabled by admin %L.", sMap, client);
	Log("togdblpressblocker.log", sBuffer);
	
	GetLists();	//rebuild lists
	ResetButtons();
	SetButtonGlows();
}

public Action OnRoundStart(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	ResetButtons();
	SetButtonGlows();
}

//////////////////////////////////////////////////////////////////////////
///////////////////////////// Admin Commands /////////////////////////////
//////////////////////////////////////////////////////////////////////////

public Action Cmd_ResetButtons(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, "\x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	PrintToChatAll("%s%s%N has reset (unlocked) the buttons!", g_bCSGO? CSGO_RED : CSS_RED, TAG, client);
	
	ResetButtons();
	SetButtonGlows();
	return Plugin_Handled;
}

public Action Cmd_PreGlow(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, "l"))
	{
		PrintToChat(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	if(iArgs != 3)
	{
		PrintToChat(client, " \x03%sUsage: sm_preglow <R value> <G value> <B value>!", TAG);
		return Plugin_Handled;
	}
	
	char sMap[128], sPath[256], sTemp[30];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sPath, sizeof(sPath), "configs/togdblpressblocker/%s.cfg", sMap);
	int iTemp1, iTemp2, iTemp3;
	
	///// R /////
	GetCmdArg(1, sTemp, sizeof(sTemp));
	iTemp1 = StringToInt(sTemp);
	if(iTemp1 > 255)
	{
		PrintToChat(client, " \x03%sEach RGB value can only range from 0 - 255!", TAG);
		return Plugin_Handled;
	}
	
	///// G /////
	GetCmdArg(2, sTemp, sizeof(sTemp));
	iTemp2 = StringToInt(sTemp);
	if(iTemp2 > 255)
	{
		PrintToChat(client, " \x03%sEach RGB value can only range from 0 - 255!", TAG);
		return Plugin_Handled;
	}
	
	///// B /////
	GetCmdArg(3, sTemp, sizeof(sTemp));
	iTemp3 = StringToInt(sTemp);
	if(iTemp3 > 255)
	{
		PrintToChat(client, " \x03%sEach RGB value can only range from 0 - 255!", TAG);
		return Plugin_Handled;
	}
	
	//if all values are good, write to global variables
	g_iRGB_Pre_R = iTemp1;
	g_iRGB_Pre_G = iTemp2;
	g_iRGB_Pre_B = iTemp3;
	
	Format(sTemp, sizeof(sTemp), "PREGLOW %i %i %i", g_iRGB_Pre_R, g_iRGB_Pre_G, g_iRGB_Pre_B);
	
	RemoveFileLine_Contains(sPath, "PREGLOW");
	WriteLineToFile(sPath, sTemp);
	
	GetLists();
	SetButtonGlows();

	PrintToChat(client, "%s%sUnpressed buttons will now glow (if able) with RGB value: \x01%i %i %i", g_bCSGO? CSGO_RED : CSS_RED, TAG, g_iRGB_Pre_R, g_iRGB_Pre_G, g_iRGB_Pre_B);
	
	return Plugin_Handled;
}

public Action Cmd_PostGlow(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	if(!HasFlags(client, "l"))
	{
		PrintToChat(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	if(iArgs != 3)
	{
		PrintToChat(client, " \x03%sUsage: sm_postglow <R value> <G value> <B value>!", TAG);
		return Plugin_Handled;
	}
	
	char sMap[128], sPath[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sPath, sizeof(sPath), "configs/togdblpressblocker/%s.cfg", sMap);
	
	char sTemp[30];
	int iTemp1, iTemp2, iTemp3;
	
	///// R /////
	GetCmdArg(1, sTemp, sizeof(sTemp));
	iTemp1 = StringToInt(sTemp);
	if(iTemp1 > 255)
	{
		PrintToChat(client, " \x03%sEach RGB value can only range from 0 - 255!", TAG);
		return Plugin_Handled;
	}
	
	///// G /////
	GetCmdArg(2, sTemp, sizeof(sTemp));
	iTemp2 = StringToInt(sTemp);
	if(iTemp2 > 255)
	{
		PrintToChat(client, " \x03%sEach RGB value can only range from 0 - 255!", TAG);
		return Plugin_Handled;
	}
	
	///// B /////
	GetCmdArg(3, sTemp, sizeof(sTemp));
	iTemp3 = StringToInt(sTemp);
	if(iTemp3 > 255)
	{
		PrintToChat(client, " \x03%sEach RGB value can only range from 0 - 255!", TAG);
		return Plugin_Handled;
	}
	
	//if all values are good, write to global variables
	g_iRGB_Post_R = iTemp1;
	g_iRGB_Post_G = iTemp2;
	g_iRGB_Post_B = iTemp3;
	
	Format(sTemp, sizeof(sTemp), "POSTGLOW %i %i %i", g_iRGB_Post_R, g_iRGB_Post_G, g_iRGB_Post_B);
	
	RemoveFileLine_Contains(sPath, "POSTGLOW");
	WriteLineToFile(sPath, sTemp);
	
	GetLists();
	SetButtonGlows();

	PrintToChat(client, "%s%sPressed buttons will now glow (if able) with RGB value: \x01%i %i %i", g_bCSGO? CSGO_RED : CSS_RED, TAG, g_iRGB_Post_R, g_iRGB_Post_G, g_iRGB_Post_B);
	
	return Plugin_Handled;
}

public Action Cmd_IgnoreButton(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	int iEntID = GetClientAimTarget(client, false);
	if(iEntID != -1)
	{
		if(IsValidEntity(iEntID))
		{
			// Get classname from entity
			char sClassName[128];
			GetEntityClassname(iEntID, sClassName, sizeof(sClassName));
			if(!StrEqual(sClassName,"func_button",false) && !StrEqual(sClassName,"func_rot_button",false))
			{
				PrintToChat(client, " \x03%sEntity is not a valid button!", TAG);
				return Plugin_Handled;
			}
			else
			{
				int iHammerID = GetEntProp(iEntID, Prop_Data, "m_iHammerID");
				int iOrigin = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
				float fEntityPos[3];
				GetEntDataVector(iEntID, iOrigin, fEntityPos);
				int a_iEntityPos[3];
				a_iEntityPos[0] = RoundFloat(fEntityPos[0]);
				a_iEntityPos[1] = RoundFloat(fEntityPos[1]);
				a_iEntityPos[2] = RoundFloat(fEntityPos[2]);
				
				if((FindValueInArray(g_hIgnoredButtons, iHammerID) == -1) && (SearchForArrayInIgnoredOrigins(a_iEntityPos) == -1))
				{
					IgnoreButton(client, iHammerID, a_iEntityPos);
				}
				else
				{
					PrintToChat(client, " \x03%sButton is already ignored!", TAG);
				}
			}
		}
		else
		{
			PrintToChat(client, " \x03%sInvalid Entity!", TAG);
		}
	}
	else
	{
		PrintToChat(client, " \x03%sNo entities found at crosshair aim.", TAG);
	}
	return Plugin_Handled;
}

public Action Cmd_Tolerance(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	if(iArgs != 1)
	{
		PrintToChat(client, " \x03%sUsage: sm_tolerance <value>!", TAG);
		return Plugin_Handled;
	}
	
	char sTemp[30];
	GetCmdArg(1, sTemp, sizeof(sTemp));
	int iTemp = StringToInt(sTemp);
	
	if(iTemp < 1)
	{
		PrintToChat(client, " \x03%sTolerance must be greater than zero!", TAG);
		return Plugin_Handled;
	}
	
	char sMap[128], sBuffer[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sBuffer, sizeof(sBuffer), "configs/togdblpressblocker/%s.cfg", sMap);
	
	g_hTolerance.IntValue = iTemp;
	
	Format(sTemp, sizeof(sTemp), "TOLERANCE %i", iTemp);
	RemoveFileLine_Contains(sBuffer, "TOLERANCE");
	WriteLineToFile(sBuffer, sTemp);

	Format(sBuffer, sizeof(sBuffer), "Tolerance for map '%s' was adjusted to %i by admin %L).", sMap, iTemp, client);
	Log("togdblpressblocker.log", sBuffer);
	
	PrintToChat(client, " \x03%sTolerance distance for button locations is now set to %i for this map.", TAG, iTemp);

	GetLists();
	return Plugin_Handled;
}

public Action Cmd_ID(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	int iEntID = GetClientAimTarget(client, false);
	if(iEntID != -1)
	{
		ID_Ent(client, iEntID);
	}
	else
	{
		PrintToChat(client, " \x03%sNo entities found at crosshair aim.", TAG);
	}
	return Plugin_Handled;
}

public Action Cmd_RemoveAutoIgnore(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	char sMap[128], sBuffer[256], sTemp[15];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sBuffer, sizeof(sBuffer), "configs/togdblpressblocker/%s.cfg", sMap);
	
	g_hAutoIgnore.BoolValue = false;

	Format(sTemp, sizeof(sTemp), "NOAUTOIGNORE");
	WriteLineToFile(sBuffer, sTemp);

	Format(sBuffer, sizeof(sBuffer), "Auto-ignore was removed from map '%s' by admin %L.", sMap, client);
	Log("togdblpressblocker.log", sBuffer);
	
	PrintToChat(client, " \x03%sButtons will no longer be automatically ignored if triggered by the map.", TAG);
	return Plugin_Handled;
}

public Action Cmd_EnableAutoIgnore(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	char sMap[128], sBuffer[256];
	GetCurrentMap(sMap, sizeof(sMap));
	Format(sBuffer, sizeof(sBuffer), "configs/togdblpressblocker/%s.cfg", sMap);
	
	g_hAutoIgnore.BoolValue = true;

	RemoveFileLine_Equal(sBuffer, "NOAUTOIGNORE");

	Format(sBuffer, sizeof(sBuffer), "Auto-ignore was re-enabled for map '%s' by admin %L.", sMap, client);
	Log("togdblpressblocker.log", sBuffer);
	
	PrintToChat(client, " \x03%sButtons will now automatically be ignored if triggered by the map.", TAG);
	return Plugin_Handled;
}

void ID_Ent(int client, int iEntID)
{
	//Hammer ID
	int iHammerID = GetEntProp(iEntID, Prop_Data, "m_iHammerID");
	//Name
	char sButtonName[MAX_NAME_LENGTH];
	sButtonName[0] = '\0';
	GetEntPropString(iEntID, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
	if(strcmp(sButtonName, "") == 0)
	{
		sButtonName = "<no name>";
	}
	//Class
	char sClassName[128];
	GetEntityClassname(iEntID, sClassName, sizeof(sClassName));
	//Location
	int iOrigin = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
	float a_fEntityPos[3];
	GetEntDataVector(iEntID, iOrigin, a_fEntityPos);
	int a_iEntityPos[3];
	a_iEntityPos[0] = RoundFloat(a_fEntityPos[0]);
	a_iEntityPos[1] = RoundFloat(a_fEntityPos[1]);
	a_iEntityPos[2] = RoundFloat(a_fEntityPos[2]);

	PrintToChat(client, " \x03%sEntity Name: %s, Class: %s\nEntityID: %i, HammerID: %i\nOrigin: x = %i ; y = %i ; z = %i", TAG, sButtonName, sClassName, iEntID, iHammerID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
	
	if((StrContains(sClassName, "func_button", false) != -1) || (StrContains(sClassName, "func_rot_button", false) != -1))
	{
		bool bIgnored = false;
		bool bPressed = false;
		int callerRef = EntIndexToEntRef(iEntID);
		if(FindValueInArray(g_hIgnoredButtons, iHammerID) != -1)
		{
			bIgnored = true;
		}
		else if(FindValueInArray(g_hLockedButtons, callerRef) != -1)
		{
			bPressed = true;
		}
		
		if(bIgnored)
		{
			PrintToChat(client, "- BUTTON IGNORED -");
		}
		else if(bPressed)
		{
			PrintToChat(client, "- BUTTON PRESSED -");
		}
		else
		{
			PrintToChat(client, "- NOT PRESSED -");
		}
		
		
		PrintToChatAll("%s%s%N triggered a beacon on button '%s'.", g_bCSGO? CSGO_RED : CSS_RED, TAG, client, sButtonName);
		PrintToChatAll("%sEID: %i, HID: %i, Origin: %i %i %i", g_bCSGO? CSGO_RED : CSS_RED, iEntID, iHammerID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
	
		EmitAmbientSoundAny(SOUND_BLIP, a_fEntityPos, client, SNDLEVEL_RAIDSIREN);
		a_fEntityPos[2] -= 60;
		TE_SetupBeamRingPoint(a_fEntityPos, 10.0, 5000.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 5.0, 10.0, 0.7, ga_iGreyColor, 10, 0);
		TE_SendToClient(client);
		a_fEntityPos[2] += 35;
		TE_SetupBeamRingPoint(a_fEntityPos, 10.0, 2000.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 5.0, 10.0, 0.7, ga_iBlueColor, 10, 0);
		TE_SendToClient(client);
		a_fEntityPos[2] += 25;
		TE_SetupBeamRingPoint(a_fEntityPos, 10.0, 500.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 5.0, 10.0, 0.7, ga_iGreenColor, 10, 0);
		TE_SendToClient(client);
		a_fEntityPos[2] += 25;
		TE_SetupBeamRingPoint(a_fEntityPos, 10.0, 2000.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 5.0, 10.0, 0.7, ga_iOrangeColor, 10, 0);
		TE_SendToClient(client);
		a_fEntityPos[2] += 35;
		TE_SetupBeamRingPoint(a_fEntityPos, 10.0, 5000.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 5.0, 10.0, 0.7, ga_iRedColor, 10, 0);
		TE_SendToClient(client);
	}
}

public Action Cmd_ListButtons(int client, int iArgs)
{
	if(!IsValidClient(client))
	{
		ReplyToCommand(client, "You must be in game to use this command!");
		return Plugin_Handled;
	}
	
	if(!HasFlags(client, g_sAdminFlag))
	{
		ReplyToCommand(client, " \x03%sYou do not have access to this command!", TAG);
		return Plugin_Handled;
	}
	
	ButtonListMenu(client);
	
	return Plugin_Handled;
}

//////////////////////////////////////////////////////////////////////////
///////////////////////////// Misc Functions /////////////////////////////
//////////////////////////////////////////////////////////////////////////

void ResetButtons()
{
	for(int i = 0; i < GetArraySize(g_hLockedButtons); i++)
	{
		int iEntRef = GetArrayCell(g_hLockedButtons,i);
		
		if(iEntRef == -1)
		{
			continue;
		}
		
		int iEnt = EntRefToEntIndex(iEntRef);
	
		if(iEnt != -1 && IsValidEdict(iEnt))
		{
			SetEntityRenderMode(iEnt, RENDER_GLOW);
			SetEntityRenderColor(iEnt, 255, 255, 255, 255);
			UnlockButton(iEnt);
		}
	}
	ClearArray(g_hLockedButtons);
}

void SetButtonGlows()
{
	bool bIgnored = false;
	bool bPressed = false;
	int iEntCount = GetEntityCount();
	int iCallerEntRef;
	for(int i = 2; i <= iEntCount; i++)
	{
		if(IsValidEntity(i))
		{
			// Get classname from entity
			char sClassName[128];
			GetEntityClassname(i, sClassName, sizeof(sClassName));
			if(!StrEqual(sClassName,"func_button",false) && !StrEqual(sClassName,"func_rot_button",false))
			{
				continue;
			}
			else
			{
				int iHammerID = GetEntProp(i, Prop_Data, "m_iHammerID");

				bIgnored = false;
				bPressed = false;
				iCallerEntRef = EntIndexToEntRef(i);
				
				int iOrigin = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
				float a_fEntityPos[3];
				GetEntDataVector(i, iOrigin, a_fEntityPos);
				int a_iEntityPos[3];
				a_iEntityPos[0] = RoundFloat(a_fEntityPos[0]);
				a_iEntityPos[1] = RoundFloat(a_fEntityPos[1]);
				a_iEntityPos[2] = RoundFloat(a_fEntityPos[2]);
				
				if(g_hEnabled.BoolValue)
				{
					if(FindValueInArray(g_hIgnoredButtons, iHammerID) != -1)
					{
						bIgnored = true;
					}
					else if(SearchForArrayInIgnoredOrigins(a_iEntityPos) != -1)
					{
						bIgnored = true;
					}
					else if(FindValueInArray(g_hLockedButtons, iCallerEntRef) != -1)
					{
						bPressed = true;
					}
					
					if(bIgnored)
					{
						SetEntityRenderMode(i, RENDER_GLOW);
						SetEntityRenderColor(i, 255, 255, 255, 255);
					}
					else if(bPressed)
					{
						SetEntityRenderMode(i, RENDER_GLOW);
						SetEntityRenderColor(i, g_iRGB_Post_R, g_iRGB_Post_G, g_iRGB_Post_B, 255);
					}
					else
					{
						SetEntityRenderMode(i, RENDER_GLOW);
						SetEntityRenderColor(i, g_iRGB_Pre_R, g_iRGB_Pre_G, g_iRGB_Pre_B, 255);
					}
				}
				else
				{
					SetEntityRenderMode(i, RENDER_GLOW);
					SetEntityRenderColor(i, 255, 255, 255, 255);
				}
			}
		}
	}
}

public void OnPluginEnd()		//return buttons to normal
{
	ResetButtons();
	SetButtonGlows();
}

public void FuncButtonOutput(const char[] sOutput, int iButtonID, int iActivator, float fDelay)
{
	if(!g_hEnabled.BoolValue)
	{
		return;
	}
	
	if(!IsValidClient(iActivator))
	{
		if(g_hAutoIgnore.BoolValue)
		{
			//if button is activated by server, then it is automated by the map, and auto-added to ignore list, unless this feature is turned off for current map
			int iHammerID2 = GetEntProp(iButtonID, Prop_Data, "m_iHammerID");
			int aOrigin2 = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
			float a_fEntityPos2[3];
			GetEntDataVector(iButtonID, aOrigin2, a_fEntityPos2);
			int a_iEntityPos[3];
			a_iEntityPos[0] = RoundFloat(a_fEntityPos2[0]);
			a_iEntityPos[1] = RoundFloat(a_fEntityPos2[1]);
			a_iEntityPos[2] = RoundFloat(a_fEntityPos2[2]);
			IgnoreButton(0, iHammerID2, a_iEntityPos);
		}
		return;
	}
	
	char sClassName[MAX_NAME_LENGTH];
	GetEntityClassname(iButtonID,sClassName,sizeof(sClassName));
	if(!StrEqual(sClassName,"func_button",false) && !StrEqual(sClassName,"func_rot_button",false))
	{
		return;
	}
	else
	{
		int iHammerID = GetEntProp(iButtonID, Prop_Data, "m_iHammerID");
		int iOrigin = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
		float a_fEntityPos[3];
		GetEntDataVector(iButtonID, iOrigin, a_fEntityPos);
		int a_iEntityPos[3];
		a_iEntityPos[0] = RoundFloat(a_fEntityPos[0]);
		a_iEntityPos[1] = RoundFloat(a_fEntityPos[1]);
		a_iEntityPos[2] = RoundFloat(a_fEntityPos[2]);
		if(g_iTotalIgnored > 0)
		{
			char sButtonName[MAX_NAME_LENGTH];
			sButtonName[0] = '\0';
			GetEntPropString(iButtonID, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
			if(strcmp(sButtonName, "") == 0)
			{
				sButtonName = "<no name>";
			}

			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidClient(i))
				{
					if(HasFlags(i, g_sAdminFlag))
					{
						PrintToConsole(i, "---------------------- TDPB ----------------------");
						PrintToConsole(i, "%N has pressed button %s (HID: %i, EID: %i). Button is now disabled! ", iActivator, sButtonName, iHammerID, iButtonID);
						PrintToConsole(i, "Button Origin: x = %i ; y = %i ; z = %i", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
						PrintToConsole(i, "--------------------------------------------------");
					}
				}
			}
			if((FindValueInArray(g_hIgnoredButtons, iHammerID) != -1) || (SearchForArrayInIgnoredOrigins(a_iEntityPos) != -1))
			{
				return;		//allow button press
			}
			else
			{
				int callerRef = EntIndexToEntRef(iButtonID);
				PushArrayCell(g_hLockedButtons,callerRef);
				SetEntityRenderMode(iButtonID, RENDER_GLOW);
				SetEntityRenderColor(iButtonID, g_iRGB_Post_R, g_iRGB_Post_G, g_iRGB_Post_B,255);		//add red glow to button
				LockButton(iButtonID);
			}
		}
		else
		{
			int callerRef = EntIndexToEntRef(iButtonID);
			PushArrayCell(g_hLockedButtons,callerRef);
			SetEntityRenderMode(iButtonID, RENDER_GLOW);
			SetEntityRenderColor(iButtonID, g_iRGB_Post_R, g_iRGB_Post_G, g_iRGB_Post_B,255);		//add red glow to button
			LockButton(iButtonID);
			char sButtonName[MAX_NAME_LENGTH];
			sButtonName[0] = '\0';
			GetEntPropString(iButtonID, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
			if(strcmp(sButtonName, "") == 0)
			{
				sButtonName = "<no name>";
			}

			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidClient(i))
				{
					if(HasFlags(i, g_sAdminFlag))
					{
						PrintToConsole(i, "---------------------- TDPB ----------------------");
						PrintToConsole(i, "%N has pressed button %s (HID: %i, EID: %i). Button is now disabled! ", iActivator, sButtonName, iHammerID, iButtonID);
						PrintToConsole(i, "Button Origin: x = %i ; y = %i ; z = %i", a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
						PrintToConsole(i, "--------------------------------------------------");
					}
				}
			}
		}
	}
}

//////////////////////////////////////////////////////////////////////
///////////////////////////// Admin Menu /////////////////////////////
//////////////////////////////////////////////////////////////////////

public void OnAdminMenuReady(Handle hTopMenu)
{
	/* Block us from being called twice */
	if(hTopMenu == g_hTopMenu)
	{
		return;
	}
	
	/* Save the Handle */
	g_hTopMenu = hTopMenu;

	TopMenuObject TDPB_MainMenu = AddToTopMenu(g_hTopMenu, "togdblpressblocker", TopMenuObject_Category, Handle_Commands, INVALID_TOPMENUOBJECT);
	if(TDPB_MainMenu == INVALID_TOPMENUOBJECT)
	{
		return;
	}
	
	AddToTopMenu(g_hTopMenu, "sm_tdpb_enable", TopMenuObject_Item, AdminMenu_Enable, TDPB_MainMenu, "sm_tdpb_enable", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_buttons", TopMenuObject_Item, AdminMenu_Buttons, TDPB_MainMenu, "sm_tdpb_buttons", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_resetbuttons", TopMenuObject_Item, AdminMenu_Reset, TDPB_MainMenu, "sm_tdpb_resetbuttons", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_verifymap", TopMenuObject_Item, AdminMenu_VerifyMap, TDPB_MainMenu, "sm_tdpb_verifymap", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_ident", TopMenuObject_Item, AdminMenu_ID, TDPB_MainMenu, "sm_tdpb_ident", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_ignore", TopMenuObject_Item, AdminMenu_Ignore, TDPB_MainMenu, "sm_tdpb_ignore", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_tolerance", TopMenuObject_Item, AdminMenu_Tolerance, TDPB_MainMenu, "sm_tdpb_tolerance", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "sm_tdpb_removeautoignore", TopMenuObject_Item, AdminMenu_AutoIgnore, TDPB_MainMenu, "sm_tdpb_removeautoignore", ADMFLAG_GENERIC);
}

public int Handle_Commands(Handle hMenu, TopMenuAction action, TopMenuObject object_id, int param1, char[] sBuffer, int iMaxLen)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(sBuffer, iMaxLen, "TOGs Dbl Press Blocker");
		}
		case TopMenuAction_DisplayTitle:
		{
			Format(sBuffer, iMaxLen, "TOGs Dbl Press Blocker");
		}
	}
}

public int AdminMenu_Enable(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		if(g_hEnabled.BoolValue)
		{
			Format(sBuffer, iMaxLen, "Disable plugin for this map");
		}
		else
		{
			Format(sBuffer, iMaxLen, "Enable plugin for this map");
		}
	}
	else if(action == TopMenuAction_SelectOption)
	{
		if(!HasFlags(param, g_sAdminFlag))
		{
			PrintToChat(param, " \x03%sYou do not have access to this command!", TAG);
			RedisplayAdminMenu(hTopMenu, param);
		}
		else
		{
			if(g_hEnabled.BoolValue)
			{
				PrintToChat(param, " \x03%sTOGs Double Press Blocker is now disabled for this map! To re-enable, type !tdpb_enable", TAG);
				DisableMap(param);
			}
			else
			{
				PrintToChat(param, " \x03%sTOGs Double Press Blocker is now enabled for this map! To disable, type !tdpb_disable", TAG);
				EnableMap(param);
			}
			RedisplayAdminMenu(hTopMenu, param);
		}
	}
}

public int AdminMenu_AutoIgnore(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		if(g_hAutoIgnore.BoolValue)
		{
			Format(sBuffer, iMaxLen, "Disable auto-ignore for map");
		}
		else
		{
			Format(sBuffer, iMaxLen, "Enable auto-ignore for map");
		}
	}
	else if(action == TopMenuAction_SelectOption)
	{
		if(!HasFlags(param, g_sAdminFlag))
		{
			PrintToChat(param, " \x03%sYou do not have access to this command!", TAG);
			RedisplayAdminMenu(hTopMenu, param);
		}
		else
		{
			if(g_hAutoIgnore.BoolValue)
			{
				FakeClientCommand(param, "sm_removeautoignore");
			}
			else
			{
				FakeClientCommand(param, "sm_enableautoignore");
			}
			RedisplayAdminMenu(hTopMenu, param);
		}
	}
}

public int AdminMenu_Reset(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Reset buttons for round");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		FakeClientCommand(param, "sm_resetbuttons");
		RedisplayAdminMenu(hTopMenu, param);
	}
}

public int AdminMenu_VerifyMap(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Approve button cfg for map");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		if(!HasFlags(param, g_sAdminFlag))
		{
			PrintToChat(param, " \x03%sYou do not have access to this command!", TAG);
			RedisplayAdminMenu(hTopMenu, param);
		}
		else
		{
			PrintToChat(param, "%s%sThis will remove the message for admins to verify this map. Please make sure there are no buttons that need to be 'ignored' before you verify the map!", g_bCSGO? CSGO_RED : CSS_RED, TAG);
			Verify_Map(param);
		}
	}
}

void Verify_Map(int client)
{
	Handle hMenu = CreateMenu(VerifyMapHandler);
	SetGlobalTransTarget(client);
	SetMenuTitle(hMenu, "Verify Map");
	SetMenuExitBackButton(hMenu, true);

	AddMenuItem(hMenu, "0", "Approve Map Verification");
	AddMenuItem(hMenu, "1", "Cancel Map Verification");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int VerifyMapHandler(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			char sTemp[32];
			GetMenuItem(hMenu, param2, sTemp, sizeof(sTemp));

			int iSelected;
			iSelected = StringToInt(sTemp);

			if(!iSelected)
			{
				char sFile[256], sMap[128];
				GetCurrentMap(sMap, sizeof(sMap));
				BuildPath(Path_SM, sFile, sizeof(sFile), "configs/togdblpressblocker/%s.cfg", sMap);
				if(!FileExists(sFile))
				{
					VerifyMap(param1);
					PrintToChat(param1, " \x03%sButtons are now verified! Verify message is now disabled for map.", TAG);
				}
				else
				{
					PrintToChat(param1, " \x03%sMap file already exists! No need to verify file.", TAG);
				}
			}

			DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
		}
	}

	return;
}

public int AdminMenu_ID(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Identify Map Entity @aim");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		FakeClientCommand(param, "sm_ident");
		RedisplayAdminMenu(hTopMenu, param);
	}
}

public int AdminMenu_Ignore(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Ignore Button @aim");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		FakeClientCommand(param, "sm_ignore");
		RedisplayAdminMenu(hTopMenu, param);
	}
}

public int AdminMenu_Tolerance(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Adjust Map Tolerance");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		PrintToChat(param, " \x03%sTo adjust tolerance for location checks on buttons with no HID, type !tolerance <value>.", TAG);
		RedisplayAdminMenu(hTopMenu, param);
	}
}

public int AdminMenu_Buttons(Handle hTopMenu, TopMenuAction action, TopMenuObject object_id, int param, char[] sBuffer, int iMaxLen)		//command via admin menu
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxLen, "Buttons");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		if(!HasFlags(param, g_sAdminFlag))
		{
			PrintToChat(param, " \x03%sYou do not have access to this command!", TAG);
			RedisplayAdminMenu(hTopMenu, param);
		}
		else
		{
			ButtonListMenu(param);
		}
	}
}

void ButtonListMenu(int client)
{
	Handle hMenu = CreateMenu(ButtonsMenuHandler);
	SetGlobalTransTarget(client);
	char sBuffer[128], sInfoBuffer[128], sButtonName[MAX_NAME_LENGTH];
	int iHammerID;
	Format(sBuffer, sizeof(sBuffer), "BUTTONS\nActive Buttons: %i\nIgnored Buttons: %i", g_iTotalActive, g_iTotalIgnored);
	SetMenuTitle(hMenu, sBuffer);
	SetMenuExitBackButton(hMenu, true);
	
	if((g_iTotalActive < 1) && (g_iTotalIgnored < 1))
	{
		CloseHandle(hMenu);
		PrintToChat(client, " \x03%sThis map does not contain any applicable buttons!", TAG);
	}
	
	int EntCount = GetEntityCount();
	bool bIgnored = false;
	for(int i = 2; i <= EntCount; i++)	//start at 2, since entID 1 is the map itself
	{
		if(IsValidEntity(i))
		{
			// Get classname from entity
			char sClassName[128];
			GetEntityClassname(i, sClassName, sizeof(sClassName));
			if(!StrEqual(sClassName,"func_button",false) && !StrEqual(sClassName,"func_rot_button",false))
			{
				continue;
			}
			else
			{
				bIgnored = false;
				sButtonName = "<no name>";
				
				iHammerID = GetEntProp(i, Prop_Data, "m_iHammerID");
				
				int iOrigin = FindSendPropInfo("CBasePlayer", "m_vecOrigin");
				float a_fEntityPos[3];
				GetEntDataVector(i, iOrigin, a_fEntityPos);
				int a_iEntityPos[3];
				a_iEntityPos[0] = RoundFloat(a_fEntityPos[0]);
				a_iEntityPos[1] = RoundFloat(a_fEntityPos[1]);
				a_iEntityPos[2] = RoundFloat(a_fEntityPos[2]);

				if(g_iTotalIgnored > 0)
				{
					if((FindValueInArray(g_hIgnoredButtons, iHammerID) != -1) || (SearchForArrayInIgnoredOrigins(a_iEntityPos) != -1))
					{
						bIgnored = true;
					}
				}

				sButtonName[0] = '\0';
				GetEntPropString(i, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
				if(strcmp(sButtonName, "") == 0)
				{
					sButtonName = "<no name>";
				}
				
				if(bIgnored)
				{
					Format(sBuffer, sizeof(sBuffer), "IGNORED: %s\nHID: %i, EID: %i", sButtonName, iHammerID, i);
					Format(sInfoBuffer, sizeof(sInfoBuffer), "%i %i %i %i %i", iHammerID, i, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
				}
				else
				{
					Format(sBuffer, sizeof(sBuffer), "Enabled: %s\nHID: %i, EID: %i", sButtonName, iHammerID, i);
					Format(sInfoBuffer, sizeof(sInfoBuffer), "%i %i %i %i %i", iHammerID, i, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
				}
				
				AddMenuItem(hMenu, sInfoBuffer, sBuffer, ITEMDRAW_DEFAULT);
			}
		}
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ButtonsMenuHandler(Handle hMenu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(hMenu);
	}
	else if((action == MenuAction_Cancel) && (param2 == MenuCancel_ExitBack) && (g_hTopMenu != INVALID_HANDLE))
	{
		DisplayTopMenu(g_hTopMenu, client, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select)
	{
		char sTemp[32];
		GetMenuItem(hMenu, param2, sTemp, sizeof(sTemp));

		char a_sTempArray[5][32];
		ExplodeString(sTemp, " ", a_sTempArray, sizeof(a_sTempArray), sizeof(a_sTempArray[]));
		int iHammerID = StringToInt(a_sTempArray[0]);
		int iEntID = StringToInt(a_sTempArray[1]);
		int a_iEntityPos[3];
		a_iEntityPos[0] = StringToInt(a_sTempArray[2]);
		a_iEntityPos[1] = StringToInt(a_sTempArray[3]);
		a_iEntityPos[2] = StringToInt(a_sTempArray[4]);

		ButtonSubMenu(client, iHammerID, iEntID, a_iEntityPos);
	}
}

void ButtonSubMenu(int client, int iHammerID, int iEntID, int[] a_iEntityPos)
{
	Handle hMenu = CreateMenu(ButtonSubMenuHandler);
	SetGlobalTransTarget(client);
	char sBuffer[128], sInfoBuffer[128], sButtonName[MAX_NAME_LENGTH];
	sButtonName[0] = '\0';
	GetEntPropString(iEntID, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
	if(strcmp(sButtonName, "") == 0)
	{
		sButtonName = "<no name>";
	}
	Format(sBuffer, 128, "Button: %s\nHID: %i ; EID: %i\nOrigin: x = %i ; y = %i ; z = %i", sButtonName, iHammerID, iEntID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
	SetMenuTitle(hMenu, sBuffer);
	SetMenuExitBackButton(hMenu, true);
	
	Format(sBuffer, sizeof(sBuffer), "Trigger button");
	Format(sInfoBuffer, sizeof(sInfoBuffer), "0 %i %i %i %i %i", iHammerID, iEntID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
	AddMenuItem(hMenu, sInfoBuffer, sBuffer);
	
	if((FindValueInArray(g_hIgnoredButtons, iHammerID) != -1) || (SearchForArrayInIgnoredOrigins(a_iEntityPos) != -1))
	{
		Format(sBuffer, sizeof(sBuffer), "Enable button");
		Format(sInfoBuffer, sizeof(sInfoBuffer), "1 %i %i %i %i %i", iHammerID, iEntID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
		AddMenuItem(hMenu, sInfoBuffer, sBuffer);
	}
	else
	{
		Format(sBuffer, sizeof(sBuffer), "Disable button");
		Format(sInfoBuffer, sizeof(sInfoBuffer), "2 %i %i %i %i %i", iHammerID, iEntID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
		AddMenuItem(hMenu, sInfoBuffer, sBuffer);
	}
	
	Format(sBuffer, sizeof(sBuffer), "Get button info");
	Format(sInfoBuffer, sizeof(sInfoBuffer), "3 %i %i %i %i %i", iHammerID, iEntID, a_iEntityPos[0], a_iEntityPos[1], a_iEntityPos[2]);
	AddMenuItem(hMenu, sInfoBuffer, sBuffer);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ButtonSubMenuHandler(Handle hMenu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			ButtonListMenu(client);
		}
		case MenuAction_Select:
		{
			char sTemp[32];
			GetMenuItem(hMenu, param2, sTemp, sizeof(sTemp));

			char a_sTempArray[6][32];
			ExplodeString(sTemp, " ", a_sTempArray, sizeof(a_sTempArray), sizeof(a_sTempArray[]));
			int iOptionSelected = StringToInt(a_sTempArray[0]);
			int iHammerID = StringToInt(a_sTempArray[1]);
			int iEntID = StringToInt(a_sTempArray[2]);
			int a_iEntityPos[3];
			a_iEntityPos[0] = StringToInt(a_sTempArray[3]);
			a_iEntityPos[1] = StringToInt(a_sTempArray[4]);
			a_iEntityPos[2] = StringToInt(a_sTempArray[5]);

			switch(iOptionSelected)
			{
				case 0:
				{
					TriggerButton(client, iEntID, a_iEntityPos);
				}
				case 1:
				{
					RemoveIgnoredButton(client, iHammerID, a_iEntityPos);
					SetButtonGlows();
				}
				case 2:
				{
					IgnoreButton(client, iHammerID, a_iEntityPos);
					ResetButtons();
					SetButtonGlows();
				}
				case 3:
				{
					ID_Ent(client, iEntID);
				}
			}

			ButtonSubMenu(client, iHammerID, iEntID, a_iEntityPos);
		}
	}

	return;
}

void CreateFile(char[] sPath)
{
	WriteLineToFile(sPath, "TEMP");
	RemoveFileLine_Equal(sPath, "TEMP");
}

void WriteLineToFile(char[] sPath, char[] sText)
{
	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "%s", sPath);
	Handle hFile = OpenFile(sFile, "a");
	WriteFileLine(hFile, sText);
	if(hFile != INVALID_HANDLE)
	{
		CloseHandle(hFile);
	}
}

void RemoveFileLine_Equal(char[] sPath, char[] sText)
{
	char sFile[PLATFORM_MAX_PATH], sFileTemp[PLATFORM_MAX_PATH], sBuffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "%s", sPath);
	BuildPath(Path_SM, sFileTemp, sizeof(sFileTemp), "%s.temp", sPath);
	Handle hFile = OpenFile(sFile, "r+");
	Handle hFileTemp = OpenFile(sFileTemp, "w");
	
	if(hFile != INVALID_HANDLE)
	{
		while(ReadFileLine(hFile, sBuffer, sizeof(sBuffer)))
		{
			TrimString(sBuffer);		//remove spaces and tabs at both ends of string
			if((StrContains(sBuffer, "//") == -1) && (!StrEqual(sBuffer, "")))		//filter out comments and blank lines
			{
				if(!StrEqual(sBuffer, sText))
				{
					WriteFileLine(hFileTemp, sBuffer);
				}
			}
			else
			{
				WriteFileLine(hFileTemp, sBuffer);
			}
		}
	}
	if(hFile != INVALID_HANDLE)
	{
		CloseHandle(hFile);
	}
	if(hFileTemp != INVALID_HANDLE)
	{
		CloseHandle(hFileTemp);
	}
	DeleteFile(sFile);
	RenameFile(sFile, sFileTemp);
}

void MsgAdmins_Chat(char[] sFlags, char[] sMsg, any ...)
{
	char sFormattedMsg[500];
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			if(HasFlags(i, sFlags))
			{
				PrintToChat(i, "%s", sFormattedMsg);
			}
		}
	}
}

bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || (!IsPlayerAlive(client) && !bAllowDead))
	{
		return false;
	}
	return true;
}

bool HasFlags(int client, char[] sFlags)
{
	if(StrEqual(sFlags, "public", false) || StrEqual(sFlags, "", false))
	{
		return true;
	}
	else if(StrEqual(sFlags, "none", false))	//useful for some plugins
	{
		return false;
	}
	else if(!client)	//if rcon
	{
		return true;
	}
	else if(CheckCommandAccess(client, "sm_not_a_command", ADMFLAG_ROOT, true))
	{
		return true;
	}
	
	AdminId id = GetUserAdmin(client);
	if(id == INVALID_ADMIN_ID)
	{
		return false;
	}
	int flags, clientflags;
	clientflags = GetUserFlagBits(client);
	
	if(StrContains(sFlags, ";", false) != -1) //check if multiple strings
	{
		int i = 0, iStrCount = 0;
		while(sFlags[i] != '\0')
		{
			if(sFlags[i++] == ';')
			{
				iStrCount++;
			}
		}
		iStrCount++; //add one more for stuff after last comma
		
		char[][] a_sTempArray = new char[iStrCount][30];
		ExplodeString(sFlags, ";", a_sTempArray, iStrCount, 30);
		bool bMatching = true;
		
		for(i = 0; i < iStrCount; i++)
		{
			bMatching = true;
			flags = ReadFlagString(a_sTempArray[i]);
			for(int j = 0; j <= 20; j++)
			{
				if(bMatching)	//if still matching, continue loop
				{
					if(flags & (1<<j))
					{
						if(!(clientflags & (1<<j)))
						{
							bMatching = false;
						}
					}
				}
			}
			if(bMatching)
			{
				return true;
			}
		}
		return false;
	}
	else
	{
		flags = ReadFlagString(sFlags);
		for(int i = 0; i <= 20; i++)
		{
			if(flags & (1<<i))
			{
				if(!(clientflags & (1<<i)))
				{
					return false;
				}
			}
		}
		return true;
	}
}

stock void Log(char[] sPath, const char[] sMsg, any ...)		//TOG logging function - path is relative to logs folder.
{
	char sLogFilePath[PLATFORM_MAX_PATH], sFormattedMsg[1500];
	BuildPath(Path_SM, sLogFilePath, sizeof(sLogFilePath), "logs/%s", sPath);
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	LogToFileEx(sLogFilePath, "%s", sFormattedMsg);
}

void RemoveFileLine_Contains(char[] sPath, char[] sText)
{
	char sFile[PLATFORM_MAX_PATH], sFileTemp[PLATFORM_MAX_PATH], sBuffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "%s", sPath);
	BuildPath(Path_SM, sFileTemp, sizeof(sFileTemp), "%s.temp", sPath);
	Handle hFile = OpenFile(sFile, "r+");
	Handle hFileTemp = OpenFile(sFileTemp, "w");
	
	if(hFile != INVALID_HANDLE)
	{
		while(ReadFileLine(hFile, sBuffer, sizeof(sBuffer)))
		{
			TrimString(sBuffer);		//remove spaces and tabs at both ends of string
			if((StrContains(sBuffer, "//") == -1) && (!StrEqual(sBuffer, "")))		//filter out comments and blank lines
			{
				if(StrContains(sBuffer, sText, false) == -1)
				{
					WriteFileLine(hFileTemp, sBuffer);
				}
			}
			else
			{
				WriteFileLine(hFileTemp, sBuffer);
			}
		}
	}
	if(hFile != INVALID_HANDLE)
	{
		CloseHandle(hFile);
	}
	if(hFileTemp != INVALID_HANDLE)
	{
		CloseHandle(hFileTemp);
	}
	DeleteFile(sFile);
	RenameFile(sFile, sFileTemp);
}

/*
CHANGELOG:
	1.x
		* Plugin created.
		* Several versions iterated, but no version number was updated. or changelog
	2.0
		* Created changelog.
		* Updated all auth string queries to detect compiler version and compile code based on version.
		* Removed <tog> include, and added my functions from it directly to the plugin.
		* Miscellaneous code cleanup and renaming of variables.
		* Converted cvar cache for auto-ignore and for plugin enabled from integers to booleans.
		* Added replies to rcon cmds.
		* Added CS:GO detections and chat formatting.
		* Replaced logging code for admin info to just use %L.
		* Removed <morecolors> include, as it wasnt being used.
	3.0
		* Updated to new syntax, but without class conversion at this time.
		* Cleaned up code a bit.
		* Added cmd descriptions.
*/
