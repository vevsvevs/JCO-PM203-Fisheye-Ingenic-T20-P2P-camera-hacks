#!/bin/sh
export LD_LIBRARY_PATH='/opt/media/sdc/lib/:/lib/:/ipc/lib/'

CONFIGPATH="/opt/media/sdc/config"
LOGDIR="/opt/media/sdc/log"
LOGPATH="$LOGDIR/startup.log"

## Load some common functions:
. /opt/media/sdc/scripts/common_functions.sh

init_log()
{
    if [ ! -d $LOGDIR ]; then
        mkdir -p $LOGDIR
    fi
}

stop_cloud()
{
    echo "Stopping cloud apps" >> $LOGPATH
    ps | awk '/[a]uto_run.sh/ {print $1}' | while read PID; do kill -9 $PID; done;
    ps | awk '/[j]co_server/ {print $1}' | xargs kill -9 &>/dev/null
    ps | awk '/[t]elnetd/ {print $1}' | xargs kill -9 &>/dev/null
    ## "Magic Close" of watchdog to prevent rebooting of device.
    echo 'V'>/dev/watchdog
    echo 'V'>/dev/watchdog0    
    rm '/opt/media/mmcblk0p1/cid.txt' &>/dev/null
}

init_network()
{
    mkdir /var/network
    WIFI_CONFIG='/opt/conf/airlink/supplicant.conf'
    if [ -f "/opt/media/sdc/wpa_supplicant.conf" ]; then
        WIFI_CONFIG='/opt/media/sdc/wpa_supplicant.conf'
    fi
    
    if [ ! -f $CONFIGPATH/hostname.conf ]; then
        cp $CONFIGPATH/hostname.conf.dist $CONFIGPATH/hostname.conf
    fi
    hostname -F $CONFIGPATH/hostname.conf
    
    wpa_supplicant_status="$(wpa_supplicant -B -i wlan0 -c $WIFI_CONFIG -P /var/run/wpa_supplicant.pid)"
    echo "wpa_supplicant: $wpa_supplicant_status" >> $LOGPATH
    udhcpc_status=$(udhcpc -i wlan0 -p /var/network/udhcpc.pid -b -x hostname:"$(hostname)")
    echo "udhcpc: $udhcpc_status" >> $LOGPATH
}

sync_time()
{
    if [ ! -f $CONFIGPATH/ntp_srv.conf ]; then
        cp $CONFIGPATH/ntp_srv.conf.dist $CONFIGPATH/ntp_srv.conf
    fi
    ntp_srv="$(cat "$CONFIGPATH/ntp_srv.conf")"
    timeout -t 30 sh -c "until ping -c1 \"$ntp_srv\" &>/dev/null; do sleep 3; done";
    /opt/media/sdc/bin/busybox ntpd -p "$ntp_srv"
}

initialize_gpio()
{
    for pin in 25 26 72 81; do
        init_gpio $pin
    done
    # the ir_led pin
    echo 1 > /sys/class/gpio/gpio81/active_low
    echo "Initialized gpios" >> $LOGPATH
    
    sleep 1
    ir_led off
    ir_cut on
    blue_led off
}

init_rtsp_params()
{
    # Set default value (will be overrided if need by autostart scripts)
    motion_detection off
    # Disable virtual memory over commit check: required for running scripts when motion detected.
    # Without this 'system()' call in rtsp server fails with not enough memory error (fork() cannot allocate virtual memory).
    echo 1 > /proc/sys/vm/overcommit_memory
}

run_autostart_scripts()
{
    echo "Autostart..." >> $LOGPATH
    for i in /opt/media/sdc/config/autostart/*; do
        echo "Run $i" >> $LOGPATH
        $i
    done
}

##############################################################

echo "--------Starting Hacks--------" >> $LOGPATH
init_log
stop_cloud
init_network
sync_time
initialize_gpio
init_rtsp_params
run_autostart_scripts
echo "--------Starting Hacks Finished!--------" >> $LOGPATH
