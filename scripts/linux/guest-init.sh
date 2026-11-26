#!/opt/hexagon/busybox sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
bb=/opt/hexagon/busybox
mkdir -p /run /tmp /dev/pts /dev/shm
$bb mount -t tmpfs tmpfs /run
$bb mount -t tmpfs -o mode=1777 tmpfs /tmp
$bb mount -t tmpfs -o mode=1777 tmpfs /dev/shm
$bb mount -t devpts -o gid=5,mode=620 devpts /dev/pts
$bb ip link set lo up
$bb ip link set eth0 up
$bb ip addr add 10.0.2.15/24 dev eth0
$bb ip route add default via 10.0.2.2
printf 'nameserver 10.0.2.3\n' > /etc/resolv.conf
hostname hexagon-linux
. /opt/hexagon/seed.env
unset LOGIN_PASSWORD
stop_guest() {
    echo HEXAGON_STOPPING
    $bb kill -TERM -1 2>/dev/null
    $bb sleep 2
    $bb kill -KILL -1 2>/dev/null
    $bb sync
    if ! $bb mount -o remount,ro /; then
        echo 'HEXAGON_ERROR: filesystem is still busy; refusing forced poweroff'
        return
    fi
    $bb poweroff -f
}
trap stop_guest INT TERM
# Private local control channel; no shell commands are accepted from the host.
(
    $bb stty -F /dev/ttyS1 raw -echo
    while IFS= read -r line; do
        [ "$line" = "shutdown:$CONTROL_TOKEN" ] && kill -TERM 1
    done < /dev/ttyS1
) &
while true; do
    /usr/local/bin/tuxee serve --config /etc/hexagon-tuxee.json &
    child=$!
    echo HEXAGON_BOOTED
    wait "$child"
    echo 'HEXAGON_SERVICE_EXITED: Tuxee restarting in 2 seconds'
    $bb sleep 2
done
