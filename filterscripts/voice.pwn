#define FILTERSCRIPT
#include <a_samp>
#include <sampvoice>

#define VOICE_KEY_LOCAL 0x42
#define VOICE_KEY_GLOBAL 0x5A
#define VOICE_LOCAL_DISTANCE 40.0

new SV_GSTREAM:gstream = SV_NULL;
new SV_LSTREAM:lstream[MAX_PLAYERS] = { SV_NULL, ... };

public OnFilterScriptInit()
{
    gstream = SvCreateGStream(0xffff0000, "Global");
    print("[voice] filterscript de voz cargado (B = local, Z = global)");
    return 1;
}

public OnFilterScriptExit()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (lstream[i])
        {
            SvDeleteStream(lstream[i]);
            lstream[i] = SV_NULL;
        }
    }
    if (gstream)
    {
        SvDeleteStream(gstream);
        gstream = SV_NULL;
    }
    return 1;
}

public SV_VOID:OnPlayerActivationKeyPress(SV_UINT:playerid, SV_UINT:keyid)
{
    if (keyid == VOICE_KEY_LOCAL && lstream[playerid]) SvAttachSpeakerToStream(lstream[playerid], playerid);
    if (keyid == VOICE_KEY_GLOBAL && gstream) SvAttachSpeakerToStream(gstream, playerid);
}

public SV_VOID:OnPlayerActivationKeyRelease(SV_UINT:playerid, SV_UINT:keyid)
{
    if (keyid == VOICE_KEY_LOCAL && lstream[playerid]) SvDetachSpeakerFromStream(lstream[playerid], playerid);
    if (keyid == VOICE_KEY_GLOBAL && gstream) SvDetachSpeakerFromStream(gstream, playerid);
}

public OnPlayerConnect(playerid)
{
    if (IsPlayerNPC(playerid)) return 1;
    if (SvGetVersion(playerid) == SV_NULL)
    {
        SendClientMessage(playerid, 0xFFCC00FF, "[Voz] No tienes el plugin SampVoice 3.1 instalado.");
    }
    else if (SvHasMicro(playerid) == SV_FALSE)
    {
        SendClientMessage(playerid, 0xFFCC00FF, "[Voz] No se detecto ningun microfono.");
    }
    else if ((lstream[playerid] = SvCreateDLStreamAtPlayer(VOICE_LOCAL_DISTANCE, SV_INFINITY, playerid, 0xff0000ff, "Local")))
    {
        SendClientMessage(playerid, 0x33CC33FF, "[Voz] Chat de voz listo: B = hablar cerca, Z = hablar a todos.");
        if (gstream) SvAttachListenerToStream(gstream, playerid);
        SvAddKey(playerid, VOICE_KEY_LOCAL);
        SvAddKey(playerid, VOICE_KEY_GLOBAL);
    }
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if (lstream[playerid])
    {
        SvDeleteStream(lstream[playerid]);
        lstream[playerid] = SV_NULL;
    }
    return 1;
}
