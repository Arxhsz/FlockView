/*
 * FlockView — Flipper Zero BLE Camera Scanner
 *
 * REAL BLE SCANNING NOTE:
 * The official Flipper SDK (ufbt/fap) does not expose a BLE central/observer
 * scan API in gap.h — only peripheral/advertising is public. To wire in real
 * scan data, you need Unleashed or RogueMaster firmware which exposes
 * furi_hal_bt_start_scan() or a custom gap scanner. This app is structured so
 * that fv_ble_on_adv() is the single function you call with real scan results.
 * Until then, the app runs in honest scanning mode: animated radar, empty list.
 */

#include <furi.h>
#include <gui/gui.h>
#include <gui/view_port.h>
#include <input/input.h>
#include <notification/notification.h>
#include <notification/notification_messages.h>
#include <stdlib.h>
#include <string.h>
#include "flockview_ascii_logo.h"

/* ── Timing ─────────────────────────────────────────────────────────── */
#define FV_VERSION      "v2.0"
#define FV_AUTHOR       "by Arxhsz"
#define FV_AUTHOR_MS    1200U
#define FV_LOADING_MS   2200U
#define FV_TICK_MS      100U

/* ── BLE detection signatures (FlockSignatures.h) ───────────────────── */
#define FLOCK_MFR_ID    0x09C8U
#define MAX_DEVICES     20U
#define RSSI_HIST_LEN   24U
#define LIST_ROWS       5U

/* ── Confidence thresholds (FlockClassifier.cpp) ────────────────────── */
#define CONF_CONFIRMED  85U
#define CONF_HIGH       70U
#define CONF_LIKELY     40U
#define SCORE_NAME      45U
#define SCORE_MFR       60U
#define SCORE_OUI       15U
#define SCORE_MULTI     20U

/* ── Known Flock BLE OUIs (FlockSignatures.h FLOCK_BLE_OUIS) ────────── */
static const uint8_t FLOCK_BLE_OUIS[][3] = {
    {0x58,0x8E,0x81},{0xCC,0xCC,0xCC},{0xEC,0x1B,0xBD},
    {0x90,0x35,0xEA},{0x04,0x0D,0x84},{0xF0,0x82,0xC0},
    {0x1C,0x34,0xF1},{0x38,0x5B,0x44},{0x94,0x34,0x69},
    {0xB4,0xE3,0xF9},
};
#define FLOCK_BLE_OUI_COUNT (sizeof(FLOCK_BLE_OUIS)/sizeof(FLOCK_BLE_OUIS[0]))

/* ── Device record ───────────────────────────────────────────────────── */
typedef struct {
    char     name[24];
    char     mac[18];          /* "XX:XX:XX:XX:XX:XX\0" */
    int8_t   rssi;
    uint8_t  confidence;
    bool     has_mfr;
    bool     oui_match;
    bool     marked;
    bool     active;           /* false = slot unused */
    uint32_t last_seen_ticks;  /* tick count when last seen */
    int8_t   rssi_hist[RSSI_HIST_LEN];
    uint8_t  rssi_head;
} FVDevice;

static FVDevice  g_devs[MAX_DEVICES];
static uint8_t   g_dev_count = 0;

/* ── Screens ─────────────────────────────────────────────────────────── */
typedef enum {
    SCR_AUTHOR, SCR_LOADING, SCR_SCANNING,
    SCR_LIST, SCR_ALERT, SCR_DETAILS,
    SCR_SETTINGS, SCR_RSSI_FILTER,
} FVScreen;

/* ── Settings ────────────────────────────────────────────────────────── */
typedef enum { RF_OFF=0, RF_100, RF_90, RF_80, RF_70, RF_60 } RssiFilter;

typedef struct {
    RssiFilter rssi_filter;
    bool       favorites_only;
    bool       auto_mark;
    bool       vibration;
    bool       notif_sound;
    uint8_t    settings_sel;    /* 0-4 */
    uint8_t    rssifilter_sel;  /* 0-4 */
    /* detail screen scroll: 0=rssi, 1=mac, 2=type, 3=mfr */
    uint8_t    detail_scroll;
} FVSettings;

/* ── Events ──────────────────────────────────────────────────────────── */
typedef enum { EVT_INPUT, EVT_TICK } FVEventType;
typedef struct { FVEventType type; InputEvent input; } FVEvent;

/* ── App ─────────────────────────────────────────────────────────────── */
typedef struct {
    Gui*              gui;
    ViewPort*         vp;
    FuriMessageQueue* q;
    FuriTimer*        timer;
    FuriMutex*        mutex;
    NotificationApp*  notif;
    FVScreen   screen;
    uint32_t   elapsed_ms;
    uint8_t    progress;
    bool       running;
    uint8_t    sel;
    uint8_t    list_off;
    uint8_t    radar_step;
    bool       alert_pending;
    uint8_t    alert_idx;
    uint32_t   tick_count;
    FVSettings settings;
} FVApp;

/* ── BLE classifier (mirrors FlockClassifier.cpp) ────────────────────── */
static bool fv_oui_match(const uint8_t mac[6]) {
    for(size_t i = 0; i < FLOCK_BLE_OUI_COUNT; i++) {
        if(mac[0]==FLOCK_BLE_OUIS[i][0] &&
           mac[1]==FLOCK_BLE_OUIS[i][1] &&
           mac[2]==FLOCK_BLE_OUIS[i][2]) return true;
    }
    return false;
}

static bool fv_name_match(const char* name) {
    if(!name || !name[0]) return false;
    return strstr(name,"Flock")  || strstr(name,"FS Ext") ||
           strstr(name,"Penguin")|| strstr(name,"FlockCam")||
           strstr(name,"FS-");
}

static uint8_t fv_classify(const char* name, bool has_mfr, bool oui) {
    uint8_t s=0, nsig=0;
    if(oui)      { s+=SCORE_OUI;  nsig++; }
    if(fv_name_match(name)) { s+=SCORE_NAME; nsig++; }
    if(has_mfr)  { s+=SCORE_MFR;  nsig++; }
    if(nsig>=2)    s+=SCORE_MULTI;
    return s>100?100:s;
}

/*
 * fv_ble_on_adv — call this from a real BLE scan callback.
 * mac[6]: raw MAC bytes; name: advertisement name or ""; rssi: dBm;
 * has_mfr: true if manufacturer ID 0x09C8 present in advert data.
 * Returns true if classified as Flock device and added/updated.
 */
static bool __attribute__((unused)) fv_ble_on_adv(FVApp* app,
                           const uint8_t mac[6], const char* name,
                           int8_t rssi, bool has_mfr,
                           uint32_t current_tick) {
    bool oui = fv_oui_match(mac);
    uint8_t conf = fv_classify(name, has_mfr, oui);
    if(conf < CONF_LIKELY) return false;   /* below threshold, ignore */

    char mac_str[18];
    snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);

    furi_mutex_acquire(app->mutex, FuriWaitForever);

    /* update existing */
    for(uint8_t i=0; i<g_dev_count; i++) {
        if(strcmp(g_devs[i].mac, mac_str)==0) {
            g_devs[i].rssi       = rssi;
            g_devs[i].confidence = conf;
            g_devs[i].last_seen_ticks = current_tick;
            g_devs[i].rssi_hist[g_devs[i].rssi_head % RSSI_HIST_LEN] = rssi;
            g_devs[i].rssi_head = (g_devs[i].rssi_head+1) % RSSI_HIST_LEN;
            furi_mutex_release(app->mutex);
            return false;
        }
    }

    /* new device */
    if(g_dev_count >= MAX_DEVICES) {
        furi_mutex_release(app->mutex);
        return false;
    }
    FVDevice* d = &g_devs[g_dev_count];
    memset(d, 0, sizeof(FVDevice));
    snprintf(d->name, sizeof(d->name), "%.23s", name[0]?name:"Unknown");
    strncpy(d->mac, mac_str, sizeof(d->mac)-1);
    d->rssi            = rssi;
    d->confidence      = conf;
    d->has_mfr         = has_mfr;
    d->oui_match       = oui;
    d->active          = true;
    d->last_seen_ticks = current_tick;
    for(uint8_t j=0;j<RSSI_HIST_LEN;j++) d->rssi_hist[j]=rssi;
    g_dev_count++;

    /* trigger alert */
    app->alert_pending = true;
    app->alert_idx     = g_dev_count-1;
    if(app->screen == SCR_SCANNING) app->screen = SCR_LIST;

    furi_mutex_release(app->mutex);

    /* notification sound */
    notification_message(app->notif, &sequence_success);
    return true;
}

/* ── Signal bars ─────────────────────────────────────────────────────── */
static void fv_bars(Canvas* c, uint8_t x, uint8_t by, int8_t rssi) {
    uint8_t filled = (rssi>=-60)?4:(rssi>=-75)?3:(rssi>=-90)?2:1;
    static const uint8_t H[4]={3,5,7,9};
    for(uint8_t i=0;i<4;i++) {
        if(i<filled) canvas_draw_box(c,  x+i*4, by-H[i], 3, H[i]);
        else         canvas_draw_frame(c, x+i*4, by-H[i], 3, H[i]);
    }
}

/* ── Last-seen string ────────────────────────────────────────────────── */
static void fv_seen(uint32_t ticks_ago, char* out, size_t sz) {
    uint32_t s = (ticks_ago * FV_TICK_MS) / 1000U;
    if(s<60) snprintf(out,sz,"%lus",(unsigned long)s);
    else     snprintf(out,sz,"%lum",(unsigned long)(s/60));
}

/* ── Header — title only, NO battery icon ───────────────────────────── */
static void fv_hdr(Canvas* c, const char* t) {
    canvas_set_font(c, FontPrimary);
    canvas_draw_str(c, 2, 10, t);
    canvas_draw_line(c, 0, 12, 127, 12);
}

/* ── Author splash ───────────────────────────────────────────────────── */
static void fv_draw_author(Canvas* c) {
    canvas_draw_xbm(c,8,5,FLOCKVIEW_ASCII_LOGO_WIDTH,
                    FLOCKVIEW_ASCII_LOGO_HEIGHT,FLOCKVIEW_ASCII_LOGO_112X28);
    canvas_set_font(c, FontSecondary);
    canvas_draw_str_aligned(c,64,44,AlignCenter,AlignCenter,FV_AUTHOR);
}

/* ── Loading bar ─────────────────────────────────────────────────────── */
static void fv_draw_loading(Canvas* c, uint8_t pct) {
    canvas_draw_xbm(c,8,5,FLOCKVIEW_ASCII_LOGO_WIDTH,
                    FLOCKVIEW_ASCII_LOGO_HEIGHT,FLOCKVIEW_ASCII_LOGO_112X28);
    canvas_set_font(c, FontSecondary);
    canvas_draw_str_aligned(c,64,38,AlignCenter,AlignCenter,FV_VERSION);
    canvas_draw_frame(c,18,48,92,7);
    uint8_t f=(uint8_t)(((uint16_t)88*pct)/100U);
    if(f) canvas_draw_box(c,20,50,f,3);
    canvas_draw_str_aligned(c,64,62,AlignCenter,AlignBottom,"Scanning for Flock cameras...");
}

/* ── Scanning screen (radar, no devices found) ───────────────────────── */
static void fv_draw_scanning(Canvas* c, uint8_t step) {
    fv_hdr(c,"FLOCKVIEW");
    const int cx=64,cy=40,r=18;
    canvas_draw_circle(c,(uint8_t)cx,(uint8_t)cy,(uint8_t)r);
    canvas_draw_circle(c,(uint8_t)cx,(uint8_t)cy,9);
    canvas_draw_line(c,(uint8_t)(cx-r),(uint8_t)cy,(uint8_t)(cx+r),(uint8_t)cy);
    canvas_draw_line(c,(uint8_t)cx,(uint8_t)(cy-r),(uint8_t)cx,(uint8_t)(cy+r));
    static const int8_t SX[36]={18,17,16,14,12,10,8,6,5,3,0,-3,-5,-6,-8,-10,-12,-14,-16,-17,-18,-17,-16,-14,-12,-10,-8,-6,-5,-3,0,3,5,6,8,10};
    static const int8_t SY[36]={0,-3,-5,-6,-8,-10,-12,-14,-16,-17,-18,-17,-16,-14,-12,-10,-8,-6,-5,-3,0,3,5,6,8,10,12,14,16,17,18,17,16,14,12,10};
    uint8_t s=step%36;
    canvas_draw_line(c,(uint8_t)cx,(uint8_t)cy,(uint8_t)(cx+SX[s]),(uint8_t)(cy+SY[s]));
    canvas_set_font(c,FontSecondary);
    canvas_draw_str_aligned(c,64,58,AlignCenter,AlignBottom,"Scanning for cameras...");
    canvas_draw_str_aligned(c,64,63,AlignCenter,AlignBottom,"No cameras detected");
}

/* ── Camera list ─────────────────────────────────────────────────────── */
/* Each row 11px: space + name (~15ch)  rssi  bars  last-seen            */
static void fv_draw_list(Canvas* c, uint8_t sel, uint8_t off, uint8_t cnt) {
    fv_hdr(c,"FLOCKVIEW");
    if(cnt==0) {
        canvas_set_font(c,FontSecondary);
        canvas_draw_str_aligned(c,64,38,AlignCenter,AlignCenter,"No cameras found");
        return;
    }
    const uint8_t RH=11, Y0=24;
    for(uint8_t r=0;r<LIST_ROWS;r++) {
        uint8_t i=off+r;
        if(i>=cnt) break;
        FVDevice* d=&g_devs[i];
        uint8_t y=Y0+r*RH;
        bool sr=(i==sel);
        if(sr) {
            canvas_set_color(c,ColorBlack);
            canvas_draw_box(c,0,y-9,124,RH);
            canvas_set_color(c,ColorWhite);
        } else {
            canvas_set_color(c,ColorBlack);
        }
        canvas_set_font(c,FontSecondary);
        canvas_draw_str(c,1,y,d->marked?"*":" ");
        char nm[16]; snprintf(nm,sizeof(nm),"%.15s",d->name);
        canvas_draw_str(c,8,y,nm);
        char rs[5]; snprintf(rs,sizeof(rs),"%4d",(int)d->rssi);
        canvas_draw_str(c,71,y,rs);
        canvas_set_color(c,sr?ColorWhite:ColorBlack);
        fv_bars(c,91,y,d->rssi);
        uint32_t ago=0; /* ticks since last seen handled externally */
        UNUSED(ago);
        char ls[10]; snprintf(ls,sizeof(ls),"%lus",(unsigned long)((d->last_seen_ticks*FV_TICK_MS)/1000));
        canvas_draw_str(c,110,y,ls);
    }
    canvas_set_color(c,ColorBlack);
    /* scrollbar */
    if(cnt>LIST_ROWS) {
        uint8_t th=(uint8_t)((51*LIST_ROWS)/cnt);
        uint8_t ty=(uint8_t)(13+(51*off)/cnt);
        canvas_draw_box(c,126,ty,2,th);
    }
}

/* ── New camera alert ────────────────────────────────────────────────── */
static void fv_draw_alert(Canvas* c, uint8_t idx) {
    FVDevice* d=&g_devs[idx];
    /* bell: circle + stem lines */
    canvas_draw_circle(c,64,18,8);
    canvas_draw_line(c,56,18,56,25);
    canvas_draw_line(c,72,18,72,25);
    canvas_draw_line(c,56,25,72,25);
    canvas_draw_box(c,62,27,4,2);  /* clapper */
    canvas_set_font(c,FontPrimary);
    canvas_draw_str_aligned(c,64,37,AlignCenter,AlignBottom,"New Camera Detected!");
    canvas_set_font(c,FontSecondary);
    canvas_draw_str_aligned(c,64,49,AlignCenter,AlignBottom,d->name);
    char rs[12]; snprintf(rs,sizeof(rs),"%d dBm",(int)d->rssi);
    canvas_draw_str_aligned(c,64,58,AlignCenter,AlignBottom,rs);
    canvas_draw_str_aligned(c,64,63,AlignCenter,AlignBottom,"Press OK");
}

/* ── Device details — scrollable ─────────────────────────────────────── */
/* scroll=0: RSSI + waveform  |  scroll=1: MAC + confidence + OUI  |
   scroll=2: mark/unmark info  (up/down to scroll)                       */
static void fv_draw_details(Canvas* c, uint8_t idx, uint8_t scroll) {
    FVDevice* d=&g_devs[idx];
    /* header: name + star */
    canvas_set_font(c,FontPrimary);
    char hdr[22]; snprintf(hdr,sizeof(hdr),"%.20s",d->name);
    canvas_draw_str(c,2,10,hdr);
    canvas_set_font(c,FontSecondary);
    canvas_draw_str(c,120,10,d->marked?"*":"o");
    canvas_draw_line(c,0,12,127,12);

    if(scroll==0) {
        /* RSSI + bars + last-seen + waveform */
        canvas_set_font(c,FontSecondary);
        char rs[12]; snprintf(rs,sizeof(rs),"%d dBm",(int)d->rssi);
        canvas_draw_str(c,2,23,rs);
        fv_bars(c,50,23,d->rssi);
        char ls[8]; fv_seen(d->last_seen_ticks,ls,sizeof(ls));
        char lsrow[18]; snprintf(lsrow,sizeof(lsrow),"Seen: %s ago",ls);
        canvas_draw_str(c,2,33,lsrow);
        /* waveform 80x13 at (2,36) */
        canvas_draw_frame(c,2,36,80,13);
        uint8_t head=d->rssi_head;
        uint8_t ppy=0;
        for(uint8_t b=0;b<RSSI_HIST_LEN;b++) {
            uint8_t hi=(head+b)%RSSI_HIST_LEN;
            int8_t rv=d->rssi_hist[hi];
            int16_t h=(((int16_t)rv+100)*11)/60;
            if(h<0) h=0;
            if(h>11) h=11;
            uint8_t gx=(uint8_t)(3+(b*(78))/RSSI_HIST_LEN);
            uint8_t gy=(uint8_t)(48-(uint8_t)h);
            if(b>0) canvas_draw_line(c,(uint8_t)(3+((b-1)*78)/RSSI_HIST_LEN),ppy,gx,gy);
            ppy=gy;
        }
        canvas_draw_str(c,2,63,"< Back   v:more");
    } else if(scroll==1) {
        canvas_set_font(c,FontSecondary);
        canvas_draw_str(c,2,23,d->mac);
        char cf[18]; snprintf(cf,sizeof(cf),"Conf: %u%%",(unsigned)d->confidence);
        canvas_draw_str(c,2,35,cf);
        canvas_draw_str(c,2,46,d->oui_match?"OUI: Flock match":"OUI: no match");
        canvas_draw_str(c,2,57,d->has_mfr?"MFR: 0x09C8 OK":"MFR: not seen");
        canvas_draw_str(c,2,63,"< Back   v:more");
    } else {
        canvas_set_font(c,FontSecondary);
        canvas_draw_str(c,2,28,"OK = toggle favorite");
        canvas_draw_str(c,2,40,d->marked?"[*] Marked":"[o] Not marked");
        canvas_draw_str(c,2,63,"< Back   ^:back up");
    }
}

/* ── Settings ────────────────────────────────────────────────────────── */
static void fv_draw_settings(Canvas* c, const FVSettings* s) {
    fv_hdr(c,"SETTINGS");
    static const char* RF[]={"Off","-100","-90","-80","-70","-60"};
    struct { const char* lbl; const char* val; bool is_bool; bool bv; } rows[5]={
        {"RSSI Filter", RF[s->rssi_filter],             false, false},
        {"Fav Only",    s->favorites_only?"On":"Off",   false, false},
        {"Auto Mark",   "",                              true,  s->auto_mark},
        {"Vibration",   "",                              true,  s->vibration},
        {"Notif Sound", "",                              true,  s->notif_sound},
    };
    for(uint8_t i=0;i<5;i++) {
        uint8_t y=23+i*9;
        bool sel=(i==s->settings_sel);
        canvas_set_font(c,FontSecondary);
        if(sel){ canvas_set_color(c,ColorBlack); canvas_draw_box(c,0,y-7,128,9); canvas_set_color(c,ColorWhite); }
        else   canvas_set_color(c,ColorBlack);
        canvas_draw_str(c,2,y,sel?">": " ");
        canvas_draw_str(c,9,y,rows[i].lbl);
        if(rows[i].is_bool) canvas_draw_str(c,96,y,rows[i].bv?"[x]":"[ ]");
        else { canvas_draw_str(c,84,y,rows[i].val); canvas_draw_str(c,122,y,">"); }
    }
    canvas_set_color(c,ColorBlack);
    canvas_draw_str(c,2,63,"< Back");
}

/* ── RSSI filter ─────────────────────────────────────────────────────── */
static void fv_draw_rssi_filter(Canvas* c, uint8_t sel) {
    fv_hdr(c,"RSSI FILTER");
    static const char* O[]={"-100 dBm","-90 dBm","-80 dBm","-70 dBm","-60 dBm"};
    for(uint8_t i=0;i<5;i++) {
        uint8_t y=23+i*9;
        bool s=(i==sel);
        canvas_set_font(c,FontSecondary);
        if(s){ canvas_set_color(c,ColorBlack); canvas_draw_box(c,0,y-7,120,9); canvas_set_color(c,ColorWhite); }
        else   canvas_set_color(c,ColorBlack);
        canvas_draw_str(c,4,y,O[i]);
        canvas_set_color(c,s?ColorWhite:ColorBlack);
        canvas_draw_circle(c,120,y-3,4);
        if(s) canvas_draw_box(c,118,y-5,4,4);
    }
    canvas_set_color(c,ColorBlack);
    canvas_draw_str(c,2,63,"< Back");
}

/* ── Draw callback ───────────────────────────────────────────────────── */
static void fv_draw_cb(Canvas* c, void* ctx) {
    FVApp* app=ctx;
    furi_mutex_acquire(app->mutex,FuriWaitForever);
    FVScreen   scr  = app->screen;
    uint8_t    pct  = app->progress;
    uint8_t    sel  = app->sel;
    uint8_t    off  = app->list_off;
    uint8_t    rs   = app->radar_step;
    bool       alrt = app->alert_pending;
    uint8_t    ai   = app->alert_idx;
    uint8_t    cnt  = g_dev_count;
    FVSettings st   = app->settings;
    furi_mutex_release(app->mutex);

    canvas_clear(c);
    canvas_set_color(c,ColorBlack);

    switch(scr) {
    case SCR_AUTHOR:   fv_draw_author(c); break;
    case SCR_LOADING:  fv_draw_loading(c,pct); break;
    case SCR_SCANNING: fv_draw_scanning(c,rs); break;
    case SCR_LIST:
        if(alrt) fv_draw_alert(c,ai);
        else     fv_draw_list(c,sel,off,cnt);
        break;
    case SCR_ALERT:    fv_draw_alert(c,ai); break;
    case SCR_DETAILS:  fv_draw_details(c,sel,st.detail_scroll); break;
    case SCR_SETTINGS: fv_draw_settings(c,&st); break;
    case SCR_RSSI_FILTER: fv_draw_rssi_filter(c,st.rssifilter_sel); break;
    default: break;
    }
}

static void fv_input_cb(InputEvent* e, void* ctx) {
    FVApp* app=ctx;
    FVEvent ev={.type=EVT_INPUT,.input=*e};
    furi_message_queue_put(app->q,&ev,0);
}
static void fv_timer_cb(void* ctx) {
    FVApp* app=ctx;
    FVEvent ev={.type=EVT_TICK};
    furi_message_queue_put(app->q,&ev,0);
}

/* ── Tick ────────────────────────────────────────────────────────────── */
static void fv_tick(FVApp* app) {
    furi_mutex_acquire(app->mutex,FuriWaitForever);
    app->elapsed_ms+=FV_TICK_MS;
    app->tick_count++;
    if(app->elapsed_ms < FV_AUTHOR_MS) {
        app->screen=SCR_AUTHOR; app->progress=0;
    } else if(app->elapsed_ms < FV_AUTHOR_MS+FV_LOADING_MS) {
        app->screen=SCR_LOADING;
        uint32_t e=app->elapsed_ms-FV_AUTHOR_MS;
        uint32_t p=(e*100U)/FV_LOADING_MS;
        app->progress=(uint8_t)(p>100?100:p);
    } else if(app->screen==SCR_AUTHOR||app->screen==SCR_LOADING) {
        app->screen=SCR_SCANNING;
        app->progress=100;
    } else {
        app->radar_step=(uint8_t)((app->radar_step+1U)%36U);
        /* increment last_seen_ticks for all devices */
        if(app->tick_count%10U==0) {
            for(uint8_t i=0;i<g_dev_count;i++)
                g_devs[i].last_seen_ticks++;
        }
    }
    furi_mutex_release(app->mutex);
    view_port_update(app->vp);
}

/* ── Alloc / free ────────────────────────────────────────────────────── */
static FVApp* fv_alloc(void) {
    memset(g_devs,0,sizeof(g_devs));
    g_dev_count=0;
    FVApp* a=malloc(sizeof(FVApp));
    a->q     =furi_message_queue_alloc(8,sizeof(FVEvent));
    a->mutex =furi_mutex_alloc(FuriMutexTypeNormal);
    a->vp    =view_port_alloc();
    a->gui   =furi_record_open(RECORD_GUI);
    a->notif =furi_record_open(RECORD_NOTIFICATION);
    a->timer =furi_timer_alloc(fv_timer_cb,FuriTimerTypePeriodic,a);
    a->screen=SCR_AUTHOR;
    a->elapsed_ms=0; a->progress=0; a->running=true;
    a->sel=0; a->list_off=0; a->radar_step=0;
    a->alert_pending=false; a->alert_idx=0; a->tick_count=0;
    a->settings=(FVSettings){
        .rssi_filter=RF_90,.favorites_only=false,.auto_mark=true,
        .vibration=true,.notif_sound=true,
        .settings_sel=0,.rssifilter_sel=2,.detail_scroll=0,
    };
    view_port_draw_callback_set(a->vp,fv_draw_cb,a);
    view_port_input_callback_set(a->vp,fv_input_cb,a);
    gui_add_view_port(a->gui,a->vp,GuiLayerFullscreen);
    return a;
}
static void fv_free(FVApp* a) {
    furi_timer_stop(a->timer); furi_timer_free(a->timer);
    gui_remove_view_port(a->gui,a->vp); view_port_free(a->vp);
    furi_record_close(RECORD_GUI); furi_record_close(RECORD_NOTIFICATION);
    furi_mutex_free(a->mutex); furi_message_queue_free(a->q);
    free(a);
}

/* ── Main ────────────────────────────────────────────────────────────── */
int32_t flockview_ble_start_app(void* p) {
    UNUSED(p);
    FVApp* app=fv_alloc();
    furi_timer_start(app->timer,furi_ms_to_ticks(FV_TICK_MS));
    view_port_update(app->vp);

    while(app->running) {
        FVEvent ev;
        if(furi_message_queue_get(app->q,&ev,FuriWaitForever)!=FuriStatusOk) continue;
        if(ev.type==EVT_TICK){ fv_tick(app); continue; }
        if(ev.type!=EVT_INPUT||ev.input.type!=InputTypeShort) continue;
        InputKey k=ev.input.key;
        furi_mutex_acquire(app->mutex,FuriWaitForever);

        switch(app->screen) {
        case SCR_AUTHOR:
        case SCR_LOADING:
            if(k==InputKeyBack) app->running=false;
            break;
        case SCR_SCANNING:
            if(k==InputKeyBack) app->running=false;
            if(k==InputKeyLeft) app->screen=SCR_SETTINGS;
            break;
        case SCR_LIST:
            if(app->alert_pending) {
                if(k==InputKeyBack) app->alert_pending=false;
                if(k==InputKeyOk){ app->alert_pending=false; app->sel=app->alert_idx; app->screen=SCR_DETAILS; app->settings.detail_scroll=0; }
            } else {
                if(k==InputKeyBack) app->running=false;
                if(k==InputKeyLeft) app->screen=SCR_SETTINGS;
                if(k==InputKeyOk){ app->screen=SCR_DETAILS; app->settings.detail_scroll=0; }
                if(k==InputKeyDown&&app->sel+1<g_dev_count){ app->sel++; if(app->sel>=app->list_off+LIST_ROWS) app->list_off++; }
                if(k==InputKeyUp&&app->sel>0){ app->sel--; if(app->sel<app->list_off) app->list_off=app->sel; }
            }
            break;
        case SCR_ALERT:
            if(k==InputKeyBack) app->screen=SCR_LIST;
            if(k==InputKeyOk){ app->sel=app->alert_idx; app->screen=SCR_DETAILS; app->settings.detail_scroll=0; }
            break;
        case SCR_DETAILS:
            if(k==InputKeyBack) app->screen=SCR_LIST;
            if(k==InputKeyOk&&app->sel<g_dev_count) g_devs[app->sel].marked^=true;
            if(k==InputKeyDown&&app->settings.detail_scroll<2) app->settings.detail_scroll++;
            if(k==InputKeyUp&&app->settings.detail_scroll>0)   app->settings.detail_scroll--;
            break;
        case SCR_SETTINGS:
            if(k==InputKeyBack) { app->screen=(g_dev_count>0?SCR_LIST:SCR_SCANNING); }
            if(k==InputKeyDown&&app->settings.settings_sel<4) app->settings.settings_sel++;
            if(k==InputKeyUp&&app->settings.settings_sel>0)   app->settings.settings_sel--;
            if(k==InputKeyOk) {
                switch(app->settings.settings_sel) {
                case 0: app->screen=SCR_RSSI_FILTER; break;
                case 1: app->settings.favorites_only^=true; break;
                case 2: app->settings.auto_mark^=true; break;
                case 3: app->settings.vibration^=true; break;
                case 4: app->settings.notif_sound^=true; break;
                default: break;
                }
            }
            break;
        case SCR_RSSI_FILTER:
            if(k==InputKeyBack) app->screen=SCR_SETTINGS;
            if(k==InputKeyDown&&app->settings.rssifilter_sel<4) app->settings.rssifilter_sel++;
            if(k==InputKeyUp&&app->settings.rssifilter_sel>0)   app->settings.rssifilter_sel--;
            if(k==InputKeyOk){ app->settings.rssi_filter=(RssiFilter)(app->settings.rssifilter_sel+1); app->screen=SCR_SETTINGS; }
            break;
        default: break;
        }

        furi_mutex_release(app->mutex);
        view_port_update(app->vp);
    }
    fv_free(app);
    return 0;
}
