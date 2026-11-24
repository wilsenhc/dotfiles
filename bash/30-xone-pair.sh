# xone-pair: open the Xbox Wireless Adapter's pairing window and wait for a
# controller. Hardware-specific (xone-dongle driver); harmless without it.
# Ported from ~/.bash_aliases; see docs/bashrc.md.

# --- Xbox Wireless Adapter -------------------------------------------------
# Open the dongle's 60s pairing window and wait for a controller to connect.
#
# Implemented as a function, not an alias: an alias is plain text substitution
# and cannot force a fresh window, recover a dead radio, or wait for a result.
#
#   xone-pair
#
xone-pair() {
    local pairing count log reg fail

    pairing=$(compgen -G '/sys/bus/usb/drivers/xone-dongle/*/pairing' | head -1)

    # driver not loaded yet (machine booted without the dongle attached)
    if [[ -z $pairing ]]; then
        sudo /usr/sbin/modprobe xone_dongle 2>/dev/null
        sleep 2
        pairing=$(compgen -G '/sys/bus/usb/drivers/xone-dongle/*/pairing' | head -1)
    fi
    [[ -n $pairing ]] || {
        echo "xone-pair: no adapter bound to xone-dongle — is it plugged in?" >&2
        return 1
    }

    count=$(sed -n 's/^Active clients: *//p' \
        /sys/bus/usb/drivers/xone-dongle/*/active_clients 2>/dev/null | head -1)
    if [[ ${count:-0} -gt 0 ]]; then
        echo "note: $count controller(s) already connected."
        echo "      If a new one is not found, switch those off first — the dongle"
        echo "      stops hopping channels while a client is active."
    fi

    # A boot-time probe can run before /lib/firmware is mounted (the xone
    # modules live in the initramfs), leaving the radio without firmware.
    # Writing 1 still reports success in that state — only the 60s timeout
    # later fails with -110 — so detect it from the journal instead: a
    # firmware failure after the last module load means this probe had none.
    log=$(journalctl -k -b --no-pager -o cat 2>/dev/null) || log=""
    reg=$(printf '%s\n' "$log" | grep -n 'registered new interface driver xone-dongle' | tail -1 | cut -d: -f1)
    fail=$(printf '%s\n' "$log" | grep -n 'request firmware failed' | tail -1 | cut -d: -f1)
    if [[ -n $fail && ${fail:-0} -gt ${reg:-0} ]]; then
        echo "radio has no firmware (boot-time probe raced the root fs) — reloading the driver..."
        sudo /usr/sbin/modprobe -r xone_dongle 2>/dev/null
        sudo /usr/sbin/modprobe xone_dongle 2>/dev/null
        for _ in {1..30}; do
            [[ $(cat "$pairing" 2>/dev/null) == 1 ]] && break
            sleep 1
        done
        [[ $(cat "$pairing" 2>/dev/null) == 1 ]] || {
            echo "xone-pair: radio still dead — check: journalctl -k | grep xone_dongle" >&2
            return 1
        }
    fi

    # Force a FRESH 60s window. Writing 1 while it already reads 1 is a no-op
    # in the driver, so drop it to 0 first.
    [[ $(cat "$pairing" 2>/dev/null) == 1 ]] && echo 0 | sudo tee "$pairing" >/dev/null
    echo 1 | sudo tee "$pairing" >/dev/null

    echo "Pairing window open for 60s."
    echo "Hold the controller's pairing button until the Xbox button flashes fast."
    printf 'Waiting'

    for _ in {1..33}; do
        count=$(sed -n 's/^Active clients: *//p' \
            /sys/bus/usb/drivers/xone-dongle/*/active_clients 2>/dev/null | head -1)
        if [[ ${count:-0} -gt 0 ]]; then
            sleep 2   # let the GIP input device register
            echo
            echo "Connected — $count controller(s)."
            grep -E '^N: Name=.*[Xx]box' /proc/bus/input/devices 2>/dev/null
            ls /dev/input/js* 2>/dev/null
            return 0
        fi

        # a new pairing disables the window before the client count settles,
        # so re-check the count before declaring failure
        if [[ $(cat "$pairing" 2>/dev/null) != 1 ]]; then
            sleep 1
            count=$(sed -n 's/^Active clients: *//p' \
                /sys/bus/usb/drivers/xone-dongle/*/active_clients 2>/dev/null | head -1)
            if [[ ${count:-0} -gt 0 ]]; then
                echo
                echo "Connected — $count controller(s)."
                return 0
            fi
            echo
            echo "window closed before a controller connected" >&2
            return 1
        fi

        printf '.'
        sleep 2
    done

    echo
    echo "nothing connected within the pairing window" >&2
    return 1
}
