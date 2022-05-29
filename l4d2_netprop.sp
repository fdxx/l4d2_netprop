#pragma semicolon 1
#pragma newdecls required

#define VERSION "0.1"

#include <sourcemod>
#include <sdktools>

methodmap SendProp
{
	public bool IsNull()
	{
		return view_as<Address>(this) == Address_Null;
	}

	public int GetOffset()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(76), NumberType_Int32);
	}

	public SendTable GetDataTable()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(72), NumberType_Int32);
	}

	public SendPropType GetType()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(8), NumberType_Int32);
	}

	public int GetBits()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(12), NumberType_Int32);
	}

	public int GetName(char[] buffer, int maxlength)
	{
		Address pAdr = LoadFromAddress(view_as<Address>(this) + view_as<Address>(48), NumberType_Int32);
		return LoadStringFromAddress(pAdr, buffer, maxlength);
	}
}

methodmap SendTable
{
	public bool IsNull()
	{
		return view_as<Address>(this) == Address_Null;
	}

	public int GetPropCount()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(4), NumberType_Int32);
	}

	public int GetName(char[] buffer, int maxlength)
	{
		Address pAdr = LoadFromAddress(view_as<Address>(this) + view_as<Address>(8), NumberType_Int32);
		return LoadStringFromAddress(pAdr, buffer, maxlength);
	}

	property Address Props
	{
		public get()
			return LoadFromAddress(view_as<Address>(this), NumberType_Int32);
	}

	public SendProp GetProp(int i)
	{
		return view_as<SendProp>(this.Props + view_as<Address>(i*84));
	}
}

methodmap ServerClass
{
	public bool IsNull()
	{
		return view_as<Address>(this) == Address_Null;
	}

	public ServerClass GetNext()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(8), NumberType_Int32);
	}

	public SendTable GetSendTable()
	{
		return LoadFromAddress(view_as<Address>(this) + view_as<Address>(4), NumberType_Int32);
	}

	public int GetName(char[] buffer, int maxlength)
	{
		Address pAdr = LoadFromAddress(view_as<Address>(this), NumberType_Int32);
		return LoadStringFromAddress(pAdr, buffer, maxlength);
	}
}

enum SendPropType
{
	DPT_Int,
	DPT_Float,
	DPT_Vector,
	DPT_VectorXY,
	DPT_String,
	DPT_Array,
	DPT_DataTable,
	DPT_NUMSendPropTypes
};

enum struct SendPropData
{
	int iOffset;
	char sParent[128];
	char sName[128];
	SendPropType eType;
	int iByte;
	char sValue[128];
}

ServerClass g_pServerClassHead;
ArrayList g_aPropData[MAXPLAYERS];
int g_iMarkedEntityRef[MAXPLAYERS];
bool g_bWatch[MAXPLAYERS];
Handle g_hWatchTimer[MAXPLAYERS];
ConVar g_cvLogType, g_cvWatchInterval;
int g_iLogType;
float g_fWatchInterval;
char g_sLogPath[PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "L4D2 netprop",
	author = "Thrawn, fdxx",
	version = VERSION,
};

public void OnPluginStart()
{
	Init();

	CreateConVar("l4d2_netprop_version", VERSION, "version", FCVAR_NONE | FCVAR_DONTRECORD);

	g_cvLogType = CreateConVar("l4d2_netprop_logtype", "3", "1=PrintToChat, 2=LogToFile, 3=Both");
	g_cvWatchInterval = CreateConVar("l4d2_netprop_watchinterval", "1.0", "Watch interval");

	GetCvars();

	g_cvLogType.AddChangeHook(OnConVarChanged);
	g_cvWatchInterval.AddChangeHook(OnConVarChanged);

	RegAdminCmd("sm_netprop_select", Cmd_Select, ADMFLAG_ROOT);
	RegAdminCmd("sm_netprop_selectself", Cmd_SelectSelf, ADMFLAG_ROOT);

	RegAdminCmd("sm_netprop_watch", Cmd_Watch, ADMFLAG_ROOT);
	RegAdminCmd("sm_netprop_stopwatch", Cmd_StopWatch, ADMFLAG_ROOT);

	RegAdminCmd("sm_netprop_save", Cmd_Save, ADMFLAG_ROOT);
	RegAdminCmd("sm_netprop_compare", Cmd_Compare, ADMFLAG_ROOT);

	RegAdminCmd("sm_netprop_showall", Cmd_ShowAll, ADMFLAG_ROOT);
	RegAdminCmd("sm_netprop_output", Cmd_Output, ADMFLAG_ROOT);

	RegAdminCmd("sm_netprop_menu", Cmd_Menu, ADMFLAG_ROOT);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_iLogType = g_cvLogType.IntValue;
	g_fWatchInterval = g_cvWatchInterval.FloatValue;
}

Action Cmd_Select(int client, int args)
{
	g_bWatch[client] = false;
	int entity;

	if (args == 0)
		entity = GetClientAimTarget(client, false);
	else if (args == 1)
		entity = GetCmdArgInt(1);

	MarkEntity(client, entity);
	return Plugin_Handled;
}

Action Cmd_SelectSelf(int client, int args)
{
	g_bWatch[client] = false;
	MarkEntity(client, client);
	return Plugin_Handled;
}

void MarkEntity(int client, int entity)
{
	char sNetClass[128];

	if (IsValidEntity(entity) && GetEntityNetClass(entity, sNetClass, sizeof(sNetClass)))
	{
		SendTable pSendTable = GetSendTableByNetClass(sNetClass);
		if (!pSendTable.IsNull())
		{
			g_iMarkedEntityRef[client] = EntIndexToEntRef(entity);
			Print(client, "\x05Marked: \x04%s", sNetClass);

			delete g_aPropData[client];
			g_aPropData[client] = new ArrayList(sizeof(SendPropData));
			
			GetSendPropData(g_aPropData[client], pSendTable, 0, sNetClass);
			g_aPropData[client].Sort(Sort_Ascending, Sort_Integer); // Default sort "block 0", which is "SendPropData.iOffset".
			UpdateSendPropData(client);
		}
	}
}

Action Cmd_Watch(int client, int args)
{
	if (CheckClientSelection(client))
	{
		g_bWatch[client] = true;

		delete g_hWatchTimer[client];
		g_hWatchTimer[client] = CreateTimer(g_fWatchInterval, Watch_Timer, GetClientUserId(client), TIMER_REPEAT);
		
	}
	return Plugin_Handled;
}

Action Watch_Timer(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
	{
		if (CheckClientSelection(client) && g_bWatch[client])
		{
			UpdateSendPropData(client, true);
			return Plugin_Continue;
		}
	}
	g_hWatchTimer[client] = null;
	return Plugin_Stop;
}

Action Cmd_StopWatch(int client, int args)
{
	g_bWatch[client] = false;
	return Plugin_Handled;
}

Action Cmd_Save(int client, int args)
{
	g_bWatch[client] = false;

	if (CheckClientSelection(client))
	{
		UpdateSendPropData(client);
	}
	return Plugin_Handled;
}

Action Cmd_Compare(int client, int args)
{
	g_bWatch[client] = false;

	if (CheckClientSelection(client))
	{
		UpdateSendPropData(client, true);
	}
	return Plugin_Handled;
}

Action Cmd_ShowAll(int client, int args)
{
	g_bWatch[client] = false;

	if (CheckClientSelection(client))
	{
		UpdateSendPropData(client, _, true);
	}
	return Plugin_Handled;
}

Action Cmd_Output(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "sm_netprop_output \"name.txt\" (can with path)");
		return Plugin_Handled;
	}

	if (CheckClientSelection(client))
	{
		UpdateSendPropData(client);
	
		char sFile[PLATFORM_MAX_PATH];
		GetCmdArg(1, sFile, sizeof(sFile));
		OutputKeyValueToFile(client, sFile);
	}
	return Plugin_Handled;
}

void OutputKeyValueToFile(int client, const char[] sFile)
{
	SendPropData data;
	char sNetClass[128], sOffset[8];

	GetEntityNetClass(g_iMarkedEntityRef[client], sNetClass, sizeof(sNetClass));
	KeyValues kv = new KeyValues(sNetClass);
	int	iLength = g_aPropData[client].Length;

	for (int i = 0; i < iLength; i++)
	{
		g_aPropData[client].GetArray(i, data);
		IntToString(data.iOffset, sOffset, sizeof(sOffset));
		
		kv.JumpToKey(sOffset, true);
		kv.SetString("name", data.sName);
		if (data.sValue[0] == '\0') // If the value string is empty, the key will not be added, so set the value to a space.
			kv.SetString("value", " ");
		else kv.SetString("value", data.sValue);
		kv.SetNum("byte", data.iByte);
		kv.SetNum("type", view_as<int>(data.eType));
		kv.SetString("typeString", GetTypeString(data.eType));
		kv.SetString("parent", data.sParent);
		kv.Rewind();
	}
	
	kv.ExportToFile(sFile);
	delete kv;
}

Action Cmd_Menu(int client, int args)
{
	Menu menu = new Menu(Menu_Handler);

	menu.SetTitle("Category:");
	menu.AddItem("", "Select aiming entity");
	menu.AddItem("", "Select self");
	menu.AddItem("", "Watch");
	menu.AddItem("", "Stop watch");
	menu.AddItem("", "Save");
	menu.AddItem("", "Compare");

	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

int Menu_Handler(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (itemNum)
			{
				case 0: Cmd_Select(client, 0);
				case 1: Cmd_SelectSelf(client, 0);
				case 2: Cmd_Watch(client, 0);
				case 3: Cmd_StopWatch(client, 0);
				case 4: Cmd_Save(client, 0);
				case 5: Cmd_Compare(client, 0);
			}
			Cmd_Menu(client, 0);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

SendTable GetSendTableByNetClass(const char[] sNetClass)
{
	ServerClass pServerClass = g_pServerClassHead;
	while (!pServerClass.IsNull())
	{
		char sName[128];
		pServerClass.GetName(sName, sizeof(sName));

		if (strcmp(sName, sNetClass) == 0)
		{
			return pServerClass.GetSendTable();
		}
		pServerClass = pServerClass.GetNext();
	}
	return view_as<SendTable>(Address_Null);
}

void GetSendPropData(ArrayList array, SendTable pSendTable, int iOffsetRecursive, const char[] sParent)
{
	int iCount, i, iActualOffset, iBits, iByte;
	char sName[128];
	SendProp pSendProp;
	SendPropType eType;
	SendPropData data;
	
	iCount = pSendTable.GetPropCount();
	for (i = 0; i < iCount; i++)
	{
		pSendProp = pSendTable.GetProp(i);
		pSendProp.GetName(sName, sizeof(sName));
		iActualOffset = pSendProp.GetOffset() + iOffsetRecursive;
		eType = pSendProp.GetType();

		if (eType == DPT_DataTable)
		{
			GetSendPropData(array, pSendProp.GetDataTable(), iActualOffset, sName);
		}
		else
		{
			iBits = pSendProp.GetBits();
			iByte = 1;
			if (iBits > 8) iByte = 2;
			if (iBits > 16) iByte = 4;
			
			if (iActualOffset > 0 && array.FindValue(iActualOffset, 0) == -1) // block 0 = SendPropData.iOffset
			{
				data.iOffset = iActualOffset;
				data.eType = eType;
				data.iByte = iByte;
				strcopy(data.sParent, sizeof(data.sParent), sParent);
				strcopy(data.sName, sizeof(data.sName), sName);
				strcopy(data.sValue, sizeof(data.sValue), "unknown");

				array.PushArray(data);
			}
		}
	}
}

void UpdateSendPropData(int client, bool bShowChanges = false, bool bShowAll = false)
{
	static int i, iLength;
	static SendPropData data;
	static char sNewValue[128];
	static float fVec[3];

	if (bShowChanges || bShowAll)
		Print(client, "----------------------");
		
	iLength = g_aPropData[client].Length;
	for (i = 0; i < iLength; i++)
	{
		g_aPropData[client].GetArray(i, data);

		switch (data.eType)
		{
			case DPT_Int:
				FormatEx(sNewValue, sizeof(sNewValue), "%i", GetEntData(g_iMarkedEntityRef[client], data.iOffset, data.iByte)); // In SM, entity reference almost works on all entity index functions.

			case DPT_Float:
				FormatEx(sNewValue, sizeof(sNewValue), "%.2f", GetEntDataFloat(g_iMarkedEntityRef[client], data.iOffset));

			case DPT_String:
				GetEntDataString(g_iMarkedEntityRef[client], data.iOffset, sNewValue, sizeof(sNewValue));

			case DPT_Vector:
			{
				GetEntDataVector(g_iMarkedEntityRef[client], data.iOffset, fVec);
				FormatEx(sNewValue, sizeof(sNewValue), "%.2f %.2f %.2f", fVec[0], fVec[1], fVec[2]);
			}

			default:
				FormatEx(sNewValue, sizeof(sNewValue), "unknown");
		}

		if (bShowAll)
		{
			Print(client, "\x04%s \x05(parent: %s, Offset: %i) value: \x04%s", data.sName, data.sParent, data.iOffset, sNewValue);
		}

		if (bShowChanges && !StrEqual(data.sValue, sNewValue))
		{
			Print(client, "\x04%s \x05(parent: %s, Offset: %i) changed from \x04%s \x05to \x04%s", data.sName, data.sParent, data.iOffset, data.sValue, sNewValue);
		}

		strcopy(data.sValue, sizeof(data.sValue), sNewValue);
		g_aPropData[client].SetArray(i, data);
	}
}

bool CheckClientSelection(int client)
{
	if (g_aPropData[client] != null)
	{
		int entity = EntRefToEntIndex(g_iMarkedEntityRef[client]);
		if (entity > 0 && IsValidEntity(entity))
			return true;
	}

	Print(client, "No entity marked, or invalid entity.");
	return false;
}

void Print(int client, const char[] sMsg, any ...)
{
	char sBuffer[256];
	VFormat(sBuffer, sizeof(sBuffer), sMsg, 3);

	if (g_iLogType == 1 || g_iLogType == 3)
		PrintToChat(client, "%s", sBuffer);

	if (g_iLogType == 2 || g_iLogType == 3)
	{
		ReplaceString(sBuffer, sizeof(sBuffer), "\x04", "");
		ReplaceString(sBuffer, sizeof(sBuffer), "\x05", "");
		LogToFileEx(g_sLogPath, "%s", sBuffer);
	}
}

int LoadStringFromAddress(Address pAdr, char[] buffer, int maxlength)
{
	int i;
	char sChar;

	do
	{
		sChar = LoadFromAddress(pAdr + view_as<Address>(i), NumberType_Int8);
		buffer[i] = sChar;
	} while (sChar && ++i < maxlength - 1);

	return i;
}

char[] GetTypeString(SendPropType eType)
{
	char sBuffer[128];

	switch (eType)
	{
		case DPT_Int: strcopy(sBuffer, sizeof(sBuffer), "integer");
		case DPT_Float: strcopy(sBuffer, sizeof(sBuffer), "float");
		case DPT_Vector: strcopy(sBuffer, sizeof(sBuffer), "vector");
		case DPT_VectorXY: strcopy(sBuffer, sizeof(sBuffer), "vectorXY");
		case DPT_String: strcopy(sBuffer, sizeof(sBuffer), "string");
		case DPT_Array: strcopy(sBuffer, sizeof(sBuffer), "array");
		case DPT_DataTable: strcopy(sBuffer, sizeof(sBuffer), "datatable");
	}

	return sBuffer;
}

public void OnClientDisconnect(int client)
{
	Reset(client);
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		Reset(i);
	}
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		Reset(i);
	}
}

void Reset(int client)
{
	delete g_hWatchTimer[client];
	delete g_aPropData[client];
	g_bWatch[client] = false;
	g_iMarkedEntityRef[client] = -1;
}

void Init()
{
	StartPrepSDKCall(SDKCall_Server);
	PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN14CServerGameDLL19GetAllServerClassesEv", 0);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle hSDKCall = EndPrepSDKCall();
	if (hSDKCall == null)
		SetFailState("Failed to create SDKCall: CServerGameDLL::GetAllServerClasses");

	g_pServerClassHead = SDKCall(hSDKCall);
	if (g_pServerClassHead.IsNull())
		SetFailState("Failed to get: g_pServerClassHead");

	delete hSDKCall;
	BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/l4d2_netprop.log");
}

