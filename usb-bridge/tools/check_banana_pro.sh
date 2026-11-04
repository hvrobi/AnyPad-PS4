#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# AnyPad USB Bridge – Banana Pro (Allwinner A20) ellenőrző script, 0. fázis.
#
# CSAK OLVAS. Semmit nem telepít, nem tölt be kernelmodult, nem csatol fel
# fájlrendszert, nem ír a /sys, /proc, /boot vagy /etc alá, és nem használ
# hálózatot. Egyetlen fájlt hoz létre: a riportot (alapból az aktuális
# könyvtárban, vagy az első argumentumként megadott helyen).
#
# A riportból kiszűri a MAC-címeket, a gyári sorozatszámokat (CPU Serial,
# USB SerialNumber, SID) és a Bluetooth-eszközök nevét/címét.
#
# Használat:
#   sh check_banana_pro.sh                  # riport: ./banana_pro_report_<idő>.txt
#   sh check_banana_pro.sh /tmp/riport.txt  # riport a megadott helyre
#   sudo sh check_banana_pro.sh             # teljesebb dmesg/devicetree-olvasás
#
# A sudo csak azért kellhet, mert a dmesg olvasása nem rootként tiltva lehet
# (kernel.dmesg_restrict). A script rootként sem módosít semmit.

set -u
LC_ALL=C
export LC_ALL

REPORT=${1:-"./banana_pro_report_$(date +%Y%m%d_%H%M%S).txt"}

if [ -e "$REPORT" ]; then
    echo "A riportfájl már létezik, nem írom felül: $REPORT" >&2
    exit 1
fi

# Minden kimenet ezen a szűrőn megy át, mielőtt a riportba kerül.
redact() {
    sed -E \
        -e 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g' \
        -e 's/((Serial|SerialNumber|serial|iSerial)[[:space:]]*[:=]?[[:space:]]+)[^[:space:]].*/\1<eltávolítva>/' \
        -e 's/(sid[[:space:]]*[:=][[:space:]]*)[0-9A-Fa-fx]+/\1<eltávolítva>/I'
}

have() { command -v "$1" >/dev/null 2>&1; }

# Időkorlát a lassú/akadó parancsokra (pl. bluetoothctl dbus nélkül).
run_t() {
    if have timeout; then timeout 10 "$@"; else "$@"; fi
}

section() {
    printf '\n==================== %s ====================\n' "$1"
}

# Parancs futtatása; a hibát is a riportba írja, nem áll le.
cmd() {
    printf '\n$ %s\n' "$*"
    if have "$1"; then
        run_t "$@" 2>&1 || printf '[kilépési kód: %s]\n' "$?"
    else
        printf '[nincs telepítve: %s]\n' "$1"
    fi
}

show_file() {
    printf '\n--- %s ---\n' "$1"
    if [ -r "$1" ]; then cat "$1" 2>&1; else printf '[nem olvasható vagy nem létezik]\n'; fi
}

# Devicetree-tulajdonság (NUL-végű sztringek) olvasható alakban.
dt_prop() {
    if [ -r "$1" ]; then tr '\0' ' ' < "$1"; echo; else echo '[nincs]'; fi
}

collect() {
    section "Riport fejléc"
    echo "Script: AnyPad USB Bridge check_banana_pro.sh (0. fázis, csak olvas)"
    echo "Időpont: $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
    echo "Futtató: uid=$(id -u) ($(id -un 2>/dev/null))"
    echo "Csoportok: $(id -Gn 2>/dev/null)"

    section "Kernel és image"
    cmd uname -a
    show_file /etc/os-release
    show_file /etc/armbian-release
    show_file /etc/armbian-image-release
    show_file /etc/debian_version
    printf '\n--- /proc/device-tree/model ---\n'; dt_prop /proc/device-tree/model
    printf '\n--- /proc/device-tree/compatible ---\n'; dt_prop /proc/device-tree/compatible
    show_file /proc/cmdline
    printf '\n--- /boot/armbianEnv.txt (overlays és usb-sorok) ---\n'
    if [ -r /boot/armbianEnv.txt ]; then
        grep -E -i '^(overlay|overlays|user_overlays|overlay_prefix|fdtfile|extraargs)' /boot/armbianEnv.txt 2>&1 || echo '[nincs releváns sor]'
    else
        echo '[nincs /boot/armbianEnv.txt]'
    fi
    printf '\n--- telepített overlay-fájlok (csak nevek, usb/otg szűrve) ---\n'
    for d in /boot/dtb/overlay /boot/dtb-$(uname -r)/overlay /boot/overlay-user; do
        [ -d "$d" ] && { echo "$d:"; ls "$d" 2>/dev/null | grep -i -E 'usb|otg|musb' || echo '  [nincs usb/otg overlay]'; }
    done

    section "Kernel-konfiguráció (MUSB, ConfigFS, FunctionFS, gadget, HID)"
    KCONF=""
    if [ -r /proc/config.gz ]; then
        KCONF=/proc/config.gz
        echo "Forrás: /proc/config.gz"
        printf '\n$ zcat /proc/config.gz | grep -E %s\n' "'MUSB|CONFIGFS|USB_F_FS|LIBCOMPOSITE|USB_GADGET|HID'"
        zcat /proc/config.gz 2>&1 | grep -E 'MUSB|CONFIGFS|USB_F_FS|LIBCOMPOSITE|USB_GADGET|HID'
        printf '\n--- kiegészítő kapcsolók (PHY, OTG, bemeneti driverek) ---\n'
        zcat /proc/config.gz 2>&1 | grep -E 'PHY_SUN4I_USB|USB_OTG|EXTCON|USB_F_HID|USB_CONFIGFS_F_HID|JOYSTICK_XPAD|INPUT_UINPUT|INPUT_EVDEV|BT_HIDP|BT_HCIUART|BRCMFMAC|UHID|INPUT_JOYDEV|USB_DUMMY_HCD|USB_HIDDEV|HIDRAW|FF_MEMLESS|CONFIG_IKCONFIG'
    elif [ -r "/boot/config-$(uname -r)" ]; then
        KCONF="/boot/config-$(uname -r)"
        echo "Forrás: $KCONF (a /proc/config.gz nem érhető el)"
        printf '\n$ grep -E %s %s\n' "'MUSB|CONFIGFS|USB_F_FS|LIBCOMPOSITE|USB_GADGET|HID'" "$KCONF"
        grep -E 'MUSB|CONFIGFS|USB_F_FS|LIBCOMPOSITE|USB_GADGET|HID' "$KCONF"
        printf '\n--- kiegészítő kapcsolók (PHY, OTG, bemeneti driverek) ---\n'
        grep -E 'PHY_SUN4I_USB|USB_OTG|EXTCON|USB_F_HID|USB_CONFIGFS_F_HID|JOYSTICK_XPAD|INPUT_UINPUT|INPUT_EVDEV|BT_HIDP|BT_HCIUART|BRCMFMAC|UHID|INPUT_JOYDEV|USB_DUMMY_HCD|USB_HIDDEV|HIDRAW|FF_MEMLESS|CONFIG_IKCONFIG' "$KCONF"
    else
        echo "[Sem /proc/config.gz, sem /boot/config-$(uname -r) nem olvasható."
        echo " A /proc/config.gz-hez a 'configs' modul kellhet; a script nem tölti be.]"
    fi

    section "Modulok (lsmod és elérhetőség)"
    cmd lsmod
    printf '\n--- modinfo (csak lekérdezés, betöltés nélkül) ---\n'
    for m in musb_hdrc sunxi phy_sun4i_usb libcomposite usb_f_fs usb_f_hid configfs \
             hid_playstation hid_sony hid_nintendo hid_microsoft xpad uinput uhid hidp \
             brcmfmac hci_uart btbcm dummy_hcd; do
        if have modinfo; then
            if out=$(modinfo -F filename "$m" 2>/dev/null) && [ -n "$out" ]; then
                echo "$m: $out"
            else
                echo "$m: [nem található modulként – lehet beépített vagy hiányzik; lásd kernel-konfig]"
            fi
        fi
    done
    printf '\n--- /lib/modules/%s/kernel/drivers/usb/gadget (fájlnevek) ---\n' "$(uname -r)"
    find "/lib/modules/$(uname -r)/kernel/drivers/usb/gadget" -name '*.ko*' 2>/dev/null | sed 's#.*/##' | sort || echo '[nincs]'
    printf '\n--- beépített (builtin) modulok közül usb/musb/gadget/hid ---\n'
    if [ -r "/lib/modules/$(uname -r)/modules.builtin" ]; then
        grep -E 'musb|gadget|libcomposite|usb_f_|configfs|hid|phy-sun4i' "/lib/modules/$(uname -r)/modules.builtin" || echo '[nincs találat]'
    else
        echo '[nincs modules.builtin]'
    fi

    section "USB Device Controller (/sys/class/udc)"
    if [ -d /sys/class/udc ]; then
        n=0
        for u in /sys/class/udc/*; do
            [ -e "$u" ] || continue
            n=$((n + 1))
            echo "UDC: $(basename "$u")"
            for a in state current_speed maximum_speed is_otg is_a_peripheral a_hnp_support function; do
                [ -r "$u/$a" ] && printf '  %s = %s\n' "$a" "$(cat "$u/$a" 2>/dev/null)"
            done
        done
        echo "UDC-k száma: $n"
    else
        echo '[nincs /sys/class/udc – a gadget alrendszer nincs a kernelben vagy nincs UDC]'
    fi
    printf '\n--- musb platformeszközök és mód ---\n'
    for p in /sys/bus/platform/devices/*1c13000* /sys/bus/platform/devices/musb-hdrc*; do
        [ -e "$p" ] || continue
        echo "$p"
        [ -r "$p/mode" ] && echo "  mode = $(cat "$p/mode" 2>/dev/null)"
        [ -r "$p/vbus" ] && echo "  vbus = $(cat "$p/vbus" 2>/dev/null)"
        [ -L "$p/driver" ] && echo "  driver = $(basename "$(readlink "$p/driver")")"
    done

    section "ConfigFS és FunctionFS"
    printf '\n--- /proc/filesystems (configfs, functionfs) ---\n'
    grep -E 'configfs|functionfs' /proc/filesystems 2>&1 || echo '[configfs/functionfs nincs regisztrálva – modul nincs betöltve vagy hiányzik]'
    printf '\n--- csatolások ---\n'
    grep -E 'configfs|functionfs' /proc/mounts 2>&1 || echo '[nincs configfs/functionfs csatolás]'
    printf '\n--- /sys/kernel/config ---\n'
    if [ -d /sys/kernel/config ]; then
        ls -la /sys/kernel/config 2>&1
        if [ -d /sys/kernel/config/usb_gadget ]; then
            echo "usb_gadget könyvtár létezik (libcomposite betöltve). Meglévő gadgetek:"
            ls /sys/kernel/config/usb_gadget 2>&1
        else
            echo '[nincs /sys/kernel/config/usb_gadget – libcomposite nincs betöltve vagy configfs nincs csatolva]'
        fi
    else
        echo '[nincs /sys/kernel/config]'
    fi

    section "Devicetree: USB OTG (usb@1c13000) és PHY"
    if [ -d /proc/device-tree ]; then
        printf '\n--- minden dr_mode a devicetree-ben ---\n'
        find /proc/device-tree/ -name dr_mode 2>/dev/null | while read -r f; do
            printf '%s = %s\n' "$f" "$(dt_prop "$f")"
        done
        for node in $(find /proc/device-tree/ -maxdepth 3 -type d -name 'usb@1c13000' 2>/dev/null); do
            printf '\n--- %s ---\n' "$node"
            printf 'compatible = '; dt_prop "$node/compatible"
            printf 'status     = '; dt_prop "$node/status"
            printf 'dr_mode    = '; dt_prop "$node/dr_mode"
            [ -e "$node/extcon" ] && echo 'extcon     = [van]'
        done
        for node in $(find /proc/device-tree/ -maxdepth 3 -type d -name 'phy@1c13400' 2>/dev/null); do
            printf '\n--- %s ---\n' "$node"
            printf 'status = '; dt_prop "$node/status"
            for prop in usb0_id_det-gpios usb0_vbus_det-gpios usb0_vbus-supply usb0_vbus_power-supply usb1_vbus-supply usb2_vbus-supply; do
                if [ -e "$node/$prop" ]; then echo "$prop = [van]"; else echo "$prop = [nincs]"; fi
            done
        done
    else
        echo '[nincs /proc/device-tree]'
    fi

    section "Kernel-üzenetek (musb/usb/otg)"
    if have dmesg && dmesg >/dev/null 2>&1; then
        printf '\n$ dmesg | grep -i -E %s\n' "'musb|usb|otg'"
        dmesg 2>&1 | grep -i -E 'musb|usb|otg' | tail -n 300
    elif have journalctl && journalctl -k -b --no-pager -q >/dev/null 2>&1; then
        printf '\n$ journalctl -k -b | grep -i -E %s\n' "'musb|usb|otg'"
        journalctl -k -b --no-pager -q 2>&1 | grep -i -E 'musb|usb|otg' | tail -n 300
    else
        echo '[A kernelnapló nem olvasható ezzel a jogosultsággal. Futtasd sudo-val a teljes riporthoz.]'
    fi

    section "USB-eszközfa"
    cmd lsusb -t
    cmd lsusb

    section "Bluetooth"
    printf '\n--- /sys/class/bluetooth ---\n'
    ls /sys/class/bluetooth 2>&1 || echo '[nincs]'
    cmd rfkill list
    if have systemctl; then cmd systemctl is-active bluetooth.service; fi
    # A 'show' a vezérlő saját címét is kiírja: a redact() kitakarja.
    cmd bluetoothctl show
    printf '\n--- párosított eszközök száma (nevek és címek nélkül) ---\n'
    if have bluetoothctl; then
        c=$(run_t bluetoothctl devices Paired 2>/dev/null | grep -c '^Device' || true)
        echo "Párosított eszközök: ${c:-0}"
    fi
    printf '\n--- AP6210 / brcmfmac firmware-üzenetek ---\n'
    if have dmesg && dmesg >/dev/null 2>&1; then
        dmesg 2>&1 | grep -i -E 'brcm|bluetooth|hci|ap6210|bcm20710' | tail -n 60
    else
        echo '[kernelnapló nem olvasható]'
    fi

    section "CPU, RAM, tárhely, hő"
    show_file /proc/cpuinfo
    cmd nproc
    cmd free -m
    printf '\n--- /proc/meminfo (első 5 sor) ---\n'; head -n 5 /proc/meminfo 2>&1
    for c in /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor \
             /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq \
             /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq \
             /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies; do
        [ -r "$c" ] && printf '%s = %s\n' "$c" "$(cat "$c")"
    done
    for t in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$t" ] && printf '%s = %s\n' "$t" "$(cat "$t")"
    done
    cmd df -h /
    cmd uptime

    section "Táp (AXP209) és USB-VBUS"
    for p in /sys/class/power_supply/*; do
        [ -e "$p" ] || continue
        echo "$p:"
        for a in type online present status voltage_now current_now; do
            [ -r "$p/$a" ] && printf '  %s = %s\n' "$a" "$(cat "$p/$a" 2>/dev/null)"
        done
    done

    section "Szoftverkörnyezet (csak verziók, telepítés nélkül)"
    cmd python3 --version
    printf '\n--- Python-modulok elérhetősége (import-próba, izolált módban) ---\n'
    if have python3; then
        for mod in evdev Cryptodome Crypto functionfs; do
            if python3 -I -c "import $mod" >/dev/null 2>&1; then echo "$mod: elérhető"; else echo "$mod: nincs"; fi
        done
        python3 -I -c 'import struct; print("struct @llHHi mérete:", struct.calcsize("@llHHi"))' 2>&1
    fi
    cmd systemctl --version
    printf '\n--- libaio ---\n'
    ls /usr/lib/*/libaio.so* /lib/*/libaio.so* 2>/dev/null || echo '[libaio nem található]'
    printf '\n--- /dev/input, /dev/uinput, /dev/uhid, /dev/hidraw* ---\n'
    ls -l /dev/input /dev/uinput /dev/uhid /dev/hidraw* 2>&1
    printf '\n--- input csoport ---\n'
    getent group input 2>&1 || echo '[nincs input csoport]'

    section "Vége"
    echo "A riport kész. Ellenőrizd, mielőtt továbbadod: MAC-címek és sorozatszámok kitakarva."
}

umask 077
collect 2>&1 | redact > "$REPORT"
echo "Riport elkészült: $REPORT"
