#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "BattlefieldDuck"
#define PLUGIN_VERSION "1.00"

#include <sourcemod>
#include <sdktools>
#include <build>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[TF2] Sandbox - Mail System",
	author = PLUGIN_AUTHOR,
	description = "Compose a mail and send to the player's mailbox!",
	version = PLUGIN_VERSION,
	url = "https://tf2sandbox.tatlead.com/"
};

#define MODEL_MAILBOX "models/workshop/weapons/c_models/c_mailbox/c_mailbox.mdl"
#define SOUND_MAILBOX "ui/item_open_crate.wav"

Handle g_hSyncMailBox;

Database g_db[MAXPLAYERS + 1];
bool g_bIN_SCORE[MAXPLAYERS + 1];
bool g_bSetSubject[MAXPLAYERS + 1];
bool g_bSetContent[MAXPLAYERS + 1];

int g_iRecipientRef[MAXPLAYERS + 1];
char g_strSubject[MAXPLAYERS + 1][100];
char g_strContent[MAXPLAYERS + 1][256];
char g_strHints[MAXPLAYERS + 1][100];

public void OnPluginStart()
{
	char strPath[128];
	BuildPath(Path_SM, strPath, sizeof(strPath), "data/sqlite/tf2sbmail");
	if (!DirExists(strPath))
	{
		CreateDirectory(strPath, 511);
		
		if (!DirExists(strPath))
		{
			SetFailState("Fail to create directory (%s)", strPath);
		}
	}
	
	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_Say);
	
	RegAdminCmd("sm_sbmail", Command_SendMail, 0, "Open a menu and ready to compose a mail");
	RegAdminCmd("sm_sbinbox", Command_ViewInbox, 0, "Open a menu and view your inbox");
	
	g_hSyncMailBox = CreateHudSynchronizer();
}

public void OnClientPutInServer(int client)
{
	g_bIN_SCORE[client] = false;
	g_bSetSubject[client] = false;
	g_bSetContent[client] = false;
	
	g_iRecipientRef[client] = 0;
	g_strSubject[client] = "";
	g_strContent[client] = "";
	g_strHints[client] = "";
}

public void OnClientDisconnect(int client)
{
	if (g_db[client] != null)
	{
		delete g_db[client];
	}
}

public void OnMapStart()
{
	PrecacheSound(SOUND_MAILBOX);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	//Return if player is not alive
	if (!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	//Return if the aiming entity is invalid
	int entity = GetClientAimTarget(client, false);
	if(!IsValidEntity(entity))
	{
		return Plugin_Continue;
	}
	
	//Return if the aiming entity is not mailbox
	char strModelName[64];
	GetEntPropString(entity, Prop_Data, "m_ModelName", strModelName, sizeof(strModelName));
	if (!StrEqual(strModelName, MODEL_MAILBOX))
	{
		return Plugin_Continue;
	}
	
	//Return if the mailbox is grabbed by physgun
	float entityVecOrigin[3], clientVecOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityVecOrigin);
	if (entityVecOrigin[0] == 0.0 && entityVecOrigin[1] == 0.0 && entityVecOrigin[2] == 0.0)
	{
		return Plugin_Continue;
	}
	
	//Return if the mailbox is not within the distance
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", clientVecOrigin);
	if (GetVectorDistance(entityVecOrigin, clientVecOrigin) > 250.0)
	{
		return Plugin_Continue;
	}
	
	if (Build_ReturnEntityOwner(entity) != client)
	{
		return Plugin_Continue;
	}
	
	SetHudTextParams(-1.0, 0.2871, 0.05, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, g_hSyncMailBox, "Press [Tab] to view your mail box%s", (strlen(g_strHints[client])) ? g_strHints[client] : "");
	
	if (buttons & IN_SCORE)
	{
		if (!g_bIN_SCORE[client])
		{
			g_strHints[client] = "";
			
			int clients[MAXPLAYERS], numClients = 1;
			clients[0] = client;
			
			StopSound(entity, SNDCHAN_AUTO, SOUND_MAILBOX);
			EmitSound(clients, numClients, SOUND_MAILBOX, entity, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL);
			
			CreateTimer(2.0, Timer_StopMailBoxSound, EntIndexToEntRef(entity));
			
			Menu_MailBox(client);
		}
		
		g_bIN_SCORE[client] = true;
	}
	else
	{
		g_bIN_SCORE[client] = false;
	}
	
	return Plugin_Continue;
}

public Action Timer_StopMailBoxSound(Handle timer, int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	
	if(entity != INVALID_ENT_REFERENCE)
	{
		StopSound(entity, SNDCHAN_AUTO, SOUND_MAILBOX);
	}
}

public Action Command_SendMail(int client, int args)
{
	if (client < 0 && client > MaxClients && !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	Menu_ComposeMail(client);
	
	return Plugin_Handled;
}

public Action Command_ViewInbox(int client, int args)
{
	if (client < 0 && client > MaxClients && !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	Menu_MailBox(client);
	
	return Plugin_Handled;
}

public Action Menu_ComposeMail(int client)
{
	char menuinfo[1024];
	Menu menu = new Menu(Handler_ComposeMail);
	
	Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Compose Mail\n ");
	menu.SetTitle(menuinfo);
	
	Format(menuinfo, sizeof(menuinfo), " Set Subject\nSubject: %s\n ", g_strSubject[client]);
	menu.AddItem("SUBJECT", menuinfo);
	
	char strRecipient[100];
	int recipient = GetClientOfUserId(g_iRecipientRef[client]);
	if (recipient != 0)
	{
		GetClientName(recipient, strRecipient, sizeof(strRecipient));
	}
	
	Format(menuinfo, sizeof(menuinfo), " Select Recipient\nRecipient: %s\n ", strRecipient);
	menu.AddItem("RECEIVE", menuinfo);
	
	Format(menuinfo, sizeof(menuinfo), " Set Content\nContent:\n%s\n \n== Action ==", g_strContent[client]);
	menu.AddItem("CONTENT", menuinfo);
	
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	
	Format(menuinfo, sizeof(menuinfo), " Send Mail\n ");
	menu.AddItem("SEND", menuinfo);
	
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	
	Format(menuinfo, sizeof(menuinfo), " Clear Draft");
	menu.AddItem("CLEAR", menuinfo);
	
	menu.ExitBackButton = false;
	menu.ExitButton = true;
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Handler_ComposeMail(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		if (StrEqual(info, "SUBJECT"))
		{
			g_bSetContent[client] = false;
			g_bSetSubject[client] = true;
			Build_PrintToChat(client, "Please enter the subject:");
			PrintCenterText(client, "Please enter the subject in the chatbox");
			
			Menu_ComposeMail(client);
		}
		else if (StrEqual(info, "RECEIVE"))
		{
			Menu_ChooseRecipient(client);
		}
		else if (StrEqual(info, "CONTENT"))
		{
			g_bSetContent[client] = true;
			g_bSetSubject[client] = false;
			Build_PrintToChat(client, "Please enter the content:");
			PrintCenterText(client, "Please enter the content in the chatbox");
			
			Menu_ComposeMail(client);
		}
		else if (StrEqual(info, "SEND"))
		{
			bool canSend = true;
			
			int recipient = GetClientOfUserId(g_iRecipientRef[client]);
			if (recipient == 0)
			{
				Build_PrintToChat(client, "The recipient is invalid. Please choose another recipient.");
				canSend = false;
			}
			
			if (strlen(g_strSubject[client]) == 0)
			{
				Build_PrintToChat(client, "The subject is null. Please set the subject.");
				canSend = false;
			}
			
			if (strlen(g_strContent[client]) == 0)
			{
				Build_PrintToChat(client, "The content is null. Please set the content.");
				canSend = false;
			}
			
			if (canSend)
			{
				if (MailBox_SendMail(client, recipient, g_strSubject[client], g_strContent[client]))
				{
					Build_PrintToChat(client, "Mail sent successfully!");
					
					PrintCenterText(recipient, "%N has sent you a mail!\nPlease go to your mailbox and check it!\nCommand: !sbinbox", client);
					Format(g_strHints[recipient], 100, "\nNew mail from %N", client);
					
					g_bSetContent[client] = false;
					g_bSetSubject[client] = false;
					
					g_iRecipientRef[client] = 0;
					g_strSubject[client] = "";
					g_strContent[client] = "";
				}
			}
			
			Menu_ComposeMail(client);
		}
		else if (StrEqual(info, "CLEAR"))
		{
			g_bSetContent[client] = false;
			g_bSetSubject[client] = false;
			
			g_iRecipientRef[client] = 0;
			g_strSubject[client] = "";
			g_strContent[client] = "";
			
			Build_PrintToChat(client, "The mail draft was cleared.");
			
			Menu_ComposeMail(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Menu_ChooseRecipient(int client)
{
	char menuinfo[1024];
	Menu menu = new Menu(Handler_ChooseRecipient);
	
	Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Choose Recipient\n ");
	menu.SetTitle(menuinfo);
	
	char strClientUserID[30];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			IntToString(GetClientUserId(i), strClientUserID, sizeof(strClientUserID));
			Format(menuinfo, sizeof(menuinfo), " %N", i);
			menu.AddItem(strClientUserID, menuinfo);
		}
	}
	
	menu.ExitBackButton = true;
	menu.ExitButton = false;
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Handler_ChooseRecipient(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int userid = StringToInt(info);
		int recipient = GetClientOfUserId(userid);
		if (recipient == 0)
		{
			Build_PrintToChat(client, "Error! The recipient is invalid");
			Menu_ChooseRecipient(client);
		}
		else
		{
			g_iRecipientRef[client] = userid;
			Menu_ComposeMail(client);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack)
		{
			Menu_ComposeMail(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

#define MAXLENGTH_MESSAGE	128
#define MAXLENGTH_BUFFER	255
public Action Command_Say(int client, int args)
{
	if (!g_bSetSubject[client] && !g_bSetContent[client])
	{
		return Plugin_Continue;
	}
		
	char strMessage[MAXLENGTH_MESSAGE];
	GetCmdArgString(strMessage, sizeof(strMessage));
	StripQuotes(strMessage);
	TrimString(strMessage);
	
	if (g_bSetSubject[client])
	{
		Format(g_strSubject[client], 100, "%s", strMessage);
		
		Build_PrintToChat(client, "The subject has been set.");
		
		Menu_ComposeMail(client);
	}
	else if (g_bSetContent[client])
	{
		Format(g_strContent[client], 256, "%s", strMessage);
		
		Build_PrintToChat(client, "The content has been set.");
		
		Menu_ComposeMail(client);
	}
	
	g_bSetSubject[client] = false;
	g_bSetContent[client] = false;
	
	return Plugin_Handled;
}

public Action Menu_MailBox(int client)
{
	if (g_db[client] == null)
	{
		if (!MailBox_Connect(client))
		{
			return Plugin_Handled;
		}
	}
	
	char menuinfo[1024];
	Menu menu = new Menu(Handler_MailBox);
	
	Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Your Mail Box"..."\n ");
	menu.SetTitle(menuinfo);
	
	char query[56];
	Format(query, sizeof(query), "SELECT * FROM inbox");
	DBResultSet result = SQL_Query(g_db[client], query);
	int numMail = (result.HasResults) ? result.RowCount : 0;
	
	Format(menuinfo, sizeof(menuinfo), " Compose\n ");
	menu.AddItem("COMPOSE", menuinfo);
	
	Format(menuinfo, sizeof(menuinfo), " Inbox (%i)\n \n== Dangerous zone ==", numMail);
	menu.AddItem("INBOX", menuinfo, (numMail) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	
	Format(menuinfo, sizeof(menuinfo), " Delete all mails");
	menu.AddItem("DELETE", menuinfo);
	
	menu.ExitBackButton = false;
	menu.ExitButton = true;
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Handler_MailBox(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		if (StrEqual(info, "INBOX"))
		{
			Menu_Inbox(client, selection);
		}
		else if (StrEqual(info, "COMPOSE"))
		{
			Menu_ComposeMail(client);
		}
		else if (StrEqual(info, "DELETE"))
		{
			char query[56];
			Format(query, sizeof(query), "DELETE FROM inbox");
			SQL_Query(g_db[client], query);
			
			Menu_MailBox(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Menu_Inbox(int client, int selection)
{
	if (g_db[client] == null)
	{
		return Plugin_Handled;
	}
	
	char query[512];
	Format(query,sizeof(query), "SELECT id, name, subject FROM inbox");
	DBResultSet result = SQL_Query(g_db[client], query);
	
	int numMail = (result.HasResults) ? result.RowCount : 0;
	
	if (numMail == 0)
	{
		Menu_MailBox(client);
		return Plugin_Handled;
	}
	
	char menuinfo[1024];
	Menu menu = new Menu(Handler_Inbox);
	Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Your Mail Box >> Inbox (%i)"..."\n ", numMail);
	menu.SetTitle(menuinfo);
	
	char strID[5], strRecipient[100], strSubject[100];
	while (result.FetchRow())
	{
		IntToString(result.FetchInt(0), strID, sizeof(strID));
		result.FetchString(1, strRecipient, sizeof(strRecipient));
		result.FetchString(2, strSubject, sizeof(strSubject));
		
		if (strlen(strRecipient) > 30)
		{
			Format(strRecipient, 27, "%s", strRecipient);
			Format(strRecipient, 30, "%s...", strRecipient);
		}
		
		if (strlen(strSubject) > 30)
		{
			Format(strSubject, 27, "%s", strSubject);
			Format(strSubject, 30, "%s...", strSubject);
		}
		
		Format(menuinfo, sizeof(menuinfo), "%s\n   From: %s\n " , strSubject, strRecipient);
		menu.AddItem(strID, menuinfo);
	}
	
	menu.ExitBackButton = true;
	menu.ExitButton = false;
	menu.DisplayAt(client, RoundFloat((float(selection) / 7.0) - 0.4) * 7, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Handler_Inbox(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		Menu_ViewMail(client, StringToInt(info));
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack)
		{
			Menu_MailBox(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Menu_ViewMail(int client, int id)
{
	if (g_db[client] == null)
	{
		return Plugin_Handled;
	}
	
	char menuinfo[1024];
	Menu menu = new Menu(Handler_ViewMail);
	
	char query[512];
	Format(query,sizeof(query), "SELECT name, steamid, subject, content, datetime FROM inbox WHERE id = %i", id);
	DBResultSet result = SQL_Query(g_db[client], query);
	
	char strRecipient[100], strSteamID[20], strSubject[100], strContent[256], strTime[30];
	if (result.FetchRow())
	{
		result.FetchString(0, strRecipient, sizeof(strRecipient));
		result.FetchString(1, strSteamID, sizeof(strSteamID));
		result.FetchString(2, strSubject, sizeof(strSubject));
		result.FetchString(3, strContent, sizeof(strContent));
		result.FetchString(4, strTime, sizeof(strTime));
	}
	
	Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Your Mail Box >> Inbox >> View Mail\n \n%s\nFrom: %s (%s)\nDate: %s\n \n%s\n \n \n== Action ==", strSubject, strRecipient, strSteamID, strTime, strContent);
	menu.SetTitle(menuinfo);
	
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	menu.AddItem("", "", ITEMDRAW_NOTEXT);
	
	char strID[5];
	IntToString(id, strID, sizeof(strID));
	
	Format(menuinfo, sizeof(menuinfo), "Delete Mail");
	menu.AddItem(strID, menuinfo);
	
	menu.ExitBackButton = true;
	menu.ExitButton = false;
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Handler_ViewMail(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		char query[56];
		Format(query, sizeof(query), "DELETE FROM inbox WHERE id = %i", StringToInt(info));
		SQL_Query(g_db[client], query);
		
		Build_PrintToChat(client, "Mail deleted successfully!");
		
		Menu_Inbox(client, 0);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack)
		{
			Menu_Inbox(client, 0);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

bool MailBox_Connect(int client)
{
	char SteamID64[20];
	GetClientAuthId(client, AuthId_SteamID64, SteamID64, sizeof(SteamID64), true);
	
	char database[64];
	Format(database, sizeof(database), "tf2sbmail/%s", SteamID64);
	
	char error[255];
	g_db[client] = SQLite_UseDatabase(database, error, sizeof(error));
	
	if (g_db[client] == null)
	{
		Build_PrintToChat(client, "Fail to open your mailbox. (%s)", error);
		
		return false;
	}
	
	SQL_SetCharset(g_db[client], "utf8");
	
	SQL_Query(g_db[client], GetTableQuery());
	
	return true;
}

bool MailBox_SendMail(int sender, int recipient, char[] subject, char[] content)
{
	//Connect to recipient's database
	char SteamID64[20], database[64], error[255];
	GetClientAuthId(recipient, AuthId_SteamID64, SteamID64, sizeof(SteamID64), true);
	Format(database, sizeof(database), "tf2sbmail/%s", SteamID64);
	Database db = SQLite_UseDatabase(database, error, sizeof(error));
	if (db == null)
	{
		Build_PrintToChat(sender, "Fail to send the mail. (%s)", error);
		return false;
	}
	SQL_SetCharset(db, "utf8");
	
	//Create recipient's inbox if not exist
	SQL_Query(db, GetTableQuery());
	
	//Send mail to recipient's inbox
	char query[512];
	Format(query,sizeof(query), "INSERT INTO inbox (name, steamid, subject, content, datetime) VALUES (?, ?, ?, ?, ?);");
	DBStatement statement = SQL_PrepareQuery(db, query, error, sizeof(error));
	if (statement == null)
	{
		Build_PrintToChat(sender, "Fail to send the mail. (%s)", error);
		return false;
	}
	
	char senderName[100], senderSteamID[20], strTime[30];
	GetClientName(sender, senderName, sizeof(senderName));
	GetClientAuthId(sender, AuthId_SteamID64, senderSteamID, sizeof(senderSteamID), true);
	FormatTime(strTime, sizeof(strTime), "%c");
	
	statement.BindString(0, senderName, false);
	statement.BindString(1, senderSteamID, false);
	statement.BindString(2, subject, false);
	statement.BindString(3, content, false);
	statement.BindString(4, strTime, false);
	
	SQL_Execute(statement);
	
	delete db;
	
	return true;
}

char[] GetTableQuery()
{
	char query[512];
	Format(query, sizeof(query), 
		"CREATE TABLE IF NOT EXISTS inbox ( \
		`id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, \
		`name` VARCHAR(100), \
		`steamid` VARCHAR(20), \
		`subject` VARCHAR(100), \
		`content` VARCHAR(256), \
		`datetime` VARCHAR(30))"
	);
	
	return query;
}
