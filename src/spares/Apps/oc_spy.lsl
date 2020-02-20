/*
App Spy
This file is a part of OpenCollar.
Copyright 2020

: Contributors :

Aria (tiff589/Tashia Redrose) - (Feb 2020)
     - Misc fixes
     - Updated checkboxes to use the checkbox function, which made checking in the dialog_response section easier as well.
Sharie Criss - (Feb 2020) 
    - re-write for 7.4 collar release borrowing some functions and ideas from the old 3.x spy app
Aria (tiff589) - (July 2018-December 2019)
roan (Silkie Sabra) - (September 2018)

et al.


Licensed under the GPLv2. See LICENSE for full details.
https://github.com/OpenCollarTeam/OpenCollar
*/


/* This is an Alpha version and not feature complete
 *
 * ToDo: 
 *    Handle chat commands for managing Spy
 *    Implement ability to change sensor rate and radar distance with a reasonable list of values
 *    Cleanup and remove unneeded code
 *    Test!!!! And Test even more!!!
 *        multiple owners
 *        Multiple Own + wearer
 *         High lag areas
 *         Lots of avatars
 *        High level of attachment spam with AttChat
 *        High level of Ch 0 chat in general with AttChat
 *        Long strings (chat messages), Long strings with UTF
*/

string g_sScriptVersion = "7.4";
string g_sAppVersion = "1.0";

string g_sParentMenu = "Apps";
string g_sSubMenu = "Spy";

string g_scmd_menu = "\nTrace: Location trace\nSub Chat: Monitor Sub's speech\nAtt Chat: Monitor Sub's Attachments\nRadar: Report Nearby Avatars\n\nUse Attachment Chat monitoring with caution as attachments can be noisy.";
list g_lcmds = ["trace", "sub chat", "att chat", "radar"];

// Globals for App
integer g_itrace;        // Location Tracing
integer g_isubchat;        // Public Chat logging
integer g_iattchat;        // Public Chat for Attachments logging
integer g_iradar;        // Nearby avatar logging

string g_sLoc;            // Current Location
string g_sreport;        // Report Text Buffer

integer g_iSensorRange = 8;            // Range for nearby avatar logging
integer g_iSensorRepeat = 120;        // Frequency in seconds to check for nearby avatars

integer g_iListenerHandle;

string g_sRadarHash;
integer g_announce;


key g_kWearer;
string g_sWearerName;
list g_lMenuIDs;
integer g_iMenuStride;

integer g_iLocked=FALSE;

//MESSAGE MAP
//integer CMD_ZERO = 0;
integer CMD_OWNER = 500;
integer CMD_TRUSTED = 501;
//integer CMD_GROUP = 502;
integer CMD_WEARER = 503;
//integer CMD_EVERYONE = 504;
integer CMD_RLV_RELAY = 507;
//integer CMD_SAFEWORD = 510;
integer CMD_RELAY_SAFEWORD = 511;

integer LINK_CMD_DEBUG=1999;

integer NOTIFY = 1002;
integer REBOOT = -1000;

integer LM_SETTING_SAVE = 2000;//scripts send messages on this channel to have settings saved
//str must be in form of "token=value"
integer LM_SETTING_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer LM_SETTING_RESPONSE = 2002;//the settings script sends responses on this channel
integer LM_SETTING_DELETE = 2003;//delete token from settings
integer LM_SETTING_EMPTY = 2004;//sent when a token has no value

integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

integer RLV_CMD = 6000;
integer RLV_REFRESH = 6001;//RLV plugins should reinstate their restrictions upon receiving this message.

integer RLV_OFF = 6100; // send to inform plugins that RLV is disabled now, no message or key needed
integer RLV_ON = 6101; // send to inform plugins that RLV is enabled now, no message or key needed

integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;
string UPMENU = "BACK";
string ALL = "ALL";


DebugOutput(key kDest, list lParams) {
    llRegionSayTo(kDest, 0, llGetScriptName()+": "+llDumpList2String(lParams," "));
}

integer bool(integer a) {
    if(a)return TRUE;
    else return FALSE;
}

list g_lCheckboxes=["⬜","⬛"];

string Checkbox(integer iValue, string sLabel) {
    return llList2String(g_lCheckboxes, bool(iValue))+" "+sLabel;
}


string GetTimestamp() { // Return a string of the date and time
    integer t = (integer)llGetWallclock(); // seconds since mkIDnight

    return GetPSTDate() + " " + (string)(t / 3600) + ":" + PadNum((t % 3600) / 60) + ":" + PadNum(t % 60);
}

string PadNum(integer sValue) {
    if(sValue < 10)
    {
        return "0" + (string)sValue;
    }
    return (string)sValue;
}

string GetPSTDate() { // Convert the date from UTC to PST if GMT time is less than 8 hours after mkIDnight (and therefore tomorow's date).
    string sDateUTC = llGetDate();
    if (llGetGMTclock() < 28800) // that's 28800 seconds, a.k.a. 8 hours.
    {
        list lDateList = llParseString2List(sDateUTC, ["-", "-"], []);
        integer iYear = llList2Integer(lDateList, 0);
        integer iMonth = llList2Integer(lDateList, 1);
        integer iDay = llList2Integer(lDateList, 2);
        iDay = iDay - 1;
        return (string)iYear + "-" + (string)iMonth + "-" + (string)iDay;
    }
    return llGetDate();
}

string GetLocation() {
    vector g_vPos = llGetPos();
    return llList2String(llGetParcelDetails(llGetPos(), [PARCEL_DETAILS_NAME]),0) + " (" + llGetRegionName() + " <" + 
        (string)((integer)g_vPos.x)+","+(string)((integer)g_vPos.y)+","+(string)((integer)g_vPos.z)+">)";
}
    


Dialog(key kID, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth, string sName) {
    key kMenuID = llGenerateKey();
    llMessageLinked(LINK_SET, DIALOG, (string)kID + "|" + sPrompt + "|" + (string)iPage + "|" + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kMenuID);

    integer iIndex = llListFindList(g_lMenuIDs, [kID]);
    if (~iIndex) g_lMenuIDs = llListReplaceList(g_lMenuIDs, [kID, kMenuID, sName], iIndex, iIndex + g_iMenuStride - 1);
    else g_lMenuIDs += [kID, kMenuID, sName];
}

Menu(key kID, integer iAuth) {
    string sPrompt = "\n[Spy App]\n" + g_scmd_menu;
    list lButtons = [Checkbox(g_itrace, "Trace"), Checkbox(g_iradar, "Radar"), Checkbox(g_isubchat, "SubChat"), Checkbox(g_iattchat, "AttChat")];
    Dialog(kID, sPrompt, lButtons, [UPMENU], 0, iAuth, "Menu~Spy");
}


SaveSettings() {
    if(g_itrace)llMessageLinked(LINK_SET, LM_SETTING_SAVE, "spy_trace=1","");
    else llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_trace","");
    if(g_iradar)llMessageLinked(LINK_SET, LM_SETTING_SAVE, "spy_radar=1","");
    else llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_radar","");
    if(g_isubchat)llMessageLinked(LINK_SET, LM_SETTING_SAVE, "spy_subchat=1","");
    else llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_subchat","");
    if(g_iattchat)llMessageLinked(LINK_SET, LM_SETTING_SAVE, "spy_attchat=1","");
    else llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_attchat","");
}

UserCommand(integer iNum, string sStr, key kID) {
    if (iNum<CMD_OWNER || iNum>CMD_WEARER) return;
    if (llSubStringIndex(sStr,llToLower(g_sSubMenu)) && sStr != "menu "+g_sSubMenu) return;
    if ((iNum == CMD_OWNER || iNum == CMD_WEARER )&& sStr == "runaway") {
        g_lOwner = [];
        llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_subchat","");
        llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_attchat","");
        llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_radar","");
        llMessageLinked(LINK_SET, LM_SETTING_DELETE, "spy_trace","");    
        g_itrace = g_iradar = g_isubchat = g_iattchat = FALSE;
        return;
    }
    if (sStr==g_sSubMenu || sStr == "menu "+g_sSubMenu) Menu(kID, iNum);
    //else if (iNum!=CMD_OWNER && iNum!=CMD_TRUSTED && kID!=g_kWearer) RelayNotify(kID,"Access denied!",0);
    else {
        integer iWSuccess = 0; 
        string sChangetype = llList2String(llParseString2List(sStr, [" "], []),0);
        string sChangevalue = llList2String(llParseString2List(sStr, [" "], []),1);
        string sText;
        // handle chat commands here (FIXME)
    }
}

list g_lOwner=[];

AddLog(string msg) {
    if ((llStringLength(g_sreport) + llStringLength(msg)) >800) 
        SendLog();    // if it's going to overflow, send what's there first.
    g_sreport += msg;
    if (llStringLength(g_sreport) > 500)
        SendLog();    // If half full, send early
        
    llSetTimerEvent(20);
}

SendLog() {
    if (!llGetAttached()) {
        g_sreport = "";
        return;    // Don't send if not worn
    }
    // Send to owners
    integer i;
    if (!llStringLength(g_sreport)) return;
    if (llStringLength(g_sreport) > 900) {
        // send in chunks
    } else {
        for (i=0; i<llGetListLength(g_lOwner); i++) {
            key kAv = llList2Key(g_lOwner,i);
            SendIM(kAv, g_sreport);
        }
    }
    g_sreport = "";    // Clear buffer
}

SendIM(key kAV, string sMsg) {
    // Send via IM or chat or not at all depending on where the owner is....
    list lOD = llGetObjectDetails(kAV,[OBJECT_POS]);
    if (llGetListLength(lOD)) {
        vector vPos = llList2Vector(lOD,0);
        if (llVecDist(vPos,llGetPos()) < 20) return;    // Don't send if in chat range
    }
    do {
        if (llGetAgentSize(kAV))
            llRegionSayTo(kAV,0,llGetSubString(sMsg,0,800)); // much faster than IM if in the region
        else 
            llInstantMessage(kAV,llGetSubString(sMsg,0,800)); 
        sMsg = llGetSubString(sMsg,800,-1);
    } while (llStringLength(sMsg) >800); // less than 1024 to handle strings with UTF characters
}

UpdateSensor() {
    llSensorRemove();
    llListenRemove(g_iListenerHandle);
        
    //since we use the repeating sensor as a timer, turn it on if any of the spy reports are turned on, not just radar
    if (llGetAttached() && (g_itrace || g_iradar || g_iattchat || g_isubchat)) {
        if (!g_announce) { // Something's been turned on, let wearer know spy is active
            llOwnerSay("Spy App is active!");
        }
        g_announce = TRUE;
        llSensorRepeat("" ,"" , AGENT, g_iSensorRange, PI, g_iSensorRepeat);
        
        if (g_iattchat) 
            g_iListenerHandle = llListen(0, "", NULL_KEY , "");    // Listen to everything
        else if (g_isubchat)    
            g_iListenerHandle = llListen(0, "", g_kWearer , ""); // Not listening to attachments, so only listen to Avi if monitoring
        else g_iListenerHandle = 0;
    } else 
        g_announce = FALSE; // Reset announce
}



default
{
    on_rez(integer t) {
        if(llGetOwner()!=g_kWearer) llResetScript();
        g_sLoc = GetLocation();
        if (g_itrace) AddLog("\nLogin to " +  GetLocation()+ " at " + GetTimestamp() + ".\n");
        g_announce=FALSE; // reset to remind wearer spy is active when logging in
        UpdateSensor();
    }
    timer(){
        llSetTimerEvent(0);
        SendLog();
    }
    
    
    state_entry() {
        g_kWearer = llGetOwner();
        llMessageLinked(LINK_SET, LM_SETTING_REQUEST, "global_locked","");
        llMessageLinked(LINK_SET, LM_SETTING_REQUEST, "spy_subchat","");
        llMessageLinked(LINK_SET, LM_SETTING_REQUEST, "spy_attchat","");
        llMessageLinked(LINK_SET, LM_SETTING_REQUEST, "spy_radar","");
        llMessageLinked(LINK_SET, LM_SETTING_REQUEST, "spy_trace","");
        g_sLoc = GetLocation();
    }
    
    changed(integer iChanged) {
        if (g_itrace && ((iChanged & CHANGED_REGION) || (iChanged & CHANGED_TELEPORT))) {
            AddLog("\nTeleport from " + g_sLoc + " to " +  GetLocation()+ " at " + GetTimestamp() + ".\n");
            g_sLoc = GetLocation();
        } 
    }

    sensor(integer iNum) {
        if (g_iradar) {
            list g_lAvBuffer;
            integer n;
            if (iNum >10) iNum=10;    // Only show first 10 - yes, I know - it's arbitrary but needed for memory reasons
            for (n = 0; n < iNum; n++) {
                g_lAvBuffer += [llDetectedName(n)];
            }
            string sCurAvHash = llSHA1String(llList2CSV(g_lAvBuffer));
            if (sCurAvHash != g_sRadarHash) { // Don't continue reporting if the list has not changed
                AddLog("\nNearby Avatars: "+llList2CSV(g_lAvBuffer)+"\n");
                g_sRadarHash = sCurAvHash;
            }
        }

        SendLog();
    }
    
    no_sensor() {
        SendLog();
    }

    listen(integer iCh, string sName, key kID, string sMsg) {
        if (g_isubchat && kID == g_kWearer) AddLog("Chat from "+sName+" at " + GetTimestamp()+": "+sMsg+"\n");
        else if (g_iattchat && llGetOwnerKey(kID) == g_kWearer) AddLog("AttChat from "+sName+" at " + GetTimestamp()+": "+sMsg+"\n");
    }
    
    link_message(integer iSender,integer iNum,string sStr,key kID) {
        if(iNum >= CMD_OWNER && iNum <= CMD_WEARER) UserCommand(iNum, sStr, kID);
        else if(iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
            llMessageLinked(iSender, MENUNAME_RESPONSE, g_sParentMenu+"|"+ g_sSubMenu,"");
        else if(iNum == DIALOG_RESPONSE){
            integer iMenuIndex = llListFindList(g_lMenuIDs, [kID]);
            if(iMenuIndex!=-1){
                string sMenu = llList2String(g_lMenuIDs, iMenuIndex+1);
                g_lMenuIDs = llDeleteSubList(g_lMenuIDs, iMenuIndex-1, iMenuIndex-2+g_iMenuStride);
                list lMenuParams = llParseString2List(sStr, ["|"],[]);
                key kAv = llList2Key(lMenuParams,0);
                string sMsg = llList2String(lMenuParams,1);
                integer iAuth = llList2Integer(lMenuParams,3);
               integer iRespring=TRUE;
                if(sMenu == "Menu~Spy"){
                    if(sMsg == UPMENU){
                        iRespring=FALSE;
                        llMessageLinked(LINK_SET, iAuth, "menu "+g_sParentMenu, kAv);
                    } else {
                        if(iAuth != CMD_OWNER){
                            llMessageLinked(LINK_SET, NOTIFY, "0%NOACCESS% to spy options",kAv);
                            llMessageLinked(LINK_SET, iAuth, "menu "+g_sParentMenu, kAv);
                            return;
                        }
                    }
                    
                    if(sMsg == Checkbox(g_itrace, "Trace")){
                        g_itrace=1-g_itrace;
                    } else if(sMsg == Checkbox(g_iradar, "Radar")){
                        g_iradar=1-g_iradar;
                    } else if(sMsg == Checkbox(g_isubchat, "SubChat")){
                        g_isubchat = 1-g_isubchat;
                    }else if(sMsg == Checkbox(g_iattchat, "AttChat")){
                        g_iattchat = 1-g_iattchat;
                    }
                    
                    SaveSettings();
                    if(iRespring){
                        Menu(kAv,iAuth);
                    }
                    UpdateSensor();
                }
            }
        } else if(iNum == LM_SETTING_RESPONSE) {
            // Detect here the Settings
            list lSettings = llParseString2List(sStr, ["_","="],[]);
            if(llList2String(lSettings,0)=="global"){
                if(llList2String(lSettings,1)=="locked") {
                    g_iLocked=llList2Integer(lSettings,2);
                } else if(llList2String(lSettings,1)=="checkboxes"){
                    g_lCheckboxes = llCSV2List(llList2String(lSettings,2));
                }
            } else if(llList2String(lSettings,0)=="spy") {
                if(llList2String(lSettings,1)=="subchat")
                    g_isubchat=llList2Integer(lSettings,2);
                else if(llList2String(lSettings,1)=="attchat")
                    g_iattchat=llList2Integer(lSettings,2);
                else if(llList2String(lSettings,1)=="radar")
                    g_iradar=llList2Integer(lSettings,2);
                else if(llList2String(lSettings,1)=="trace")
                    g_itrace=llList2Integer(lSettings,2);
                UpdateSensor();
            } else if(llList2String(lSettings,0) == "auth"){
                if(llList2String(lSettings,1)=="owner"){
                    g_lOwner = llParseString2List(llList2String(lSettings,2), [","],[]);
                }
            }
        } else if(iNum == LM_SETTING_DELETE) {
            // This is recieved back from settings when a setting is deleted
            list lSettings = llParseString2List(sStr, ["_"],[]);
            if(llList2String(lSettings,0)=="global") {
                if(llList2String(lSettings,1) == "locked") g_iLocked=FALSE;
            } else if(llList2String(lSettings,0)=="spy"){
                if(llList2String(lSettings,1)=="subchat") g_isubchat=FALSE;
                else if(llList2String(lSettings,1)=="attchat") g_iattchat=FALSE;
                else if(llList2String(lSettings,1)=="radar") g_iradar=FALSE;
                else if(llList2String(lSettings,1)=="trace") g_itrace=FALSE;
            }
        } else if(iNum == LINK_CMD_DEBUG) {
            integer onlyver =0;
            if(sStr == "ver")onlyver=1;
            DebugOutput(kID, ["MAJOR VERSION", g_sScriptVersion, "APP", g_sAppVersion]);
            if(onlyver)return;
            DebugOutput(kID, ["MISC", g_itrace,g_isubchat,g_iattchat,g_iradar]);
        }

    }
}

// This file is long enough, you can stop scrolling now...
