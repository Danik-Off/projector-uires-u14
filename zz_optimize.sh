#!/system/bin/sh
# zz_optimize.sh - runs forever as root from zz_optimize.rc (service zz_optimize).
# 1) keeps Wi-Fi driver power save off (mains-powered device, lower latency)
# 2) force-stops third-party apps that stayed in background (oom_score_adj > 600) for BG_TIMEOUT seconds
# Log: /data/local/tmp/zz_optimize.log

BG_TIMEOUT=300      # seconds an app may sit in background before force-stop
INTERVAL=30         # seconds between checks
KEEP="com.spocky.projengmenu org.liskovsoft.androidtv.rukeyboard local.uires com.tvsas.*"   # shell patterns allowed

LOG=/data/local/tmp/zz_optimize.log
STATE=/data/local/tmp/zz_bg
mkdir -p "$STATE"
rm -f "$STATE"/*

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }
[ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 65536 ] && : > "$LOG"
log "start timeout=${BG_TIMEOUT}s interval=${INTERVAL}s"

PKGS=""
tick=0
while true; do
    # --- Wi-Fi power save ---
    if iw dev wlan0 get power_save 2>/dev/null | grep -q ': on'; then
        iw dev wlan0 set power_save off && log "wifi power_save -> off"
    fi

    # --- background app killer ---
    # refresh third-party package list every 10 ticks (apps may get installed)
    if [ $((tick % 10)) -eq 0 ]; then
        PKGS=""
        for p in $(pm list packages -3 2>/dev/null | sed 's/^package://'); do
            keep=0
            for k in $KEEP; do case "$p" in $k) keep=1 ;; esac; done
            [ $keep -eq 0 ] && PKGS="$PKGS $p"
        done
    fi
    tick=$((tick + 1))

    # don't count time while screensaver / screen off: user isn't "using" anything
    awake=1
    dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake' || awake=0


    for p in $PKGS; do
        pids=$(ps -A -o pid,name 2>/dev/null | grep -E " $p(:|\$)" | sed 's/^ *//' | cut -d' ' -f1)
        if [ -z "$pids" ]; then
            rm -f "$STATE/$p"
            continue
        fi
        # oom_score_adj as set by ActivityManager: 0 foreground, 100 visible, 200 perceptible,
        # 600 home (whatever launcher is current), 700 previous app, 900+ cached.
        # Anything <= 600 is "in use" -> not background, timer reset.
        minadj=1000
        for pid in $pids; do
            a=$(cat /proc/$pid/oom_score_adj 2>/dev/null) || continue
            [ "$a" -lt "$minadj" ] && minadj=$a
        done
        if [ "$minadj" -le 600 ]; then
            rm -f "$STATE/$p"
            continue
        fi
        [ "$awake" -eq 0 ] && continue
        secs=0
        [ -f "$STATE/$p" ] && secs=$(cat "$STATE/$p")
        secs=$((secs + INTERVAL))
        if [ "$secs" -ge "$BG_TIMEOUT" ]; then
            am force-stop "$p" && log "force-stop $p (background ${secs}s, pids: $(echo $pids))"
            rm -f "$STATE/$p"
        else
            echo "$secs" > "$STATE/$p"
        fi
    done

    sleep "$INTERVAL"
done
