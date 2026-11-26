#!/bin/busybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
bb=/bin/busybox
$bb --install -s /bin
mkdir -p /proc /sys /dev /run /mnt
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec </dev/console >/dev/console 2>&1
fail() { echo "HEXAGON_ERROR: $*"; sync; sleep 3; poweroff -f; }
/sbin/depmod -a || fail 'module dependency index'
for module in virtio_pci virtio_blk virtio_net ext4; do /sbin/modprobe "$module" || fail "driver $module"; done
count=0
while [ ! -b /dev/vda ]; do sleep 1; count=$((count+1)); [ "$count" -lt 20 ] || fail 'disk not found'; done
if [ "$1" != normal-boot ] && grep -q 'hexagon.install=1' /proc/cmdline; then
    # Never format an existing filesystem, even after a previous failed installation.
    if blkid /dev/vda | grep -q 'TYPE='; then
        mount /dev/vda /mnt || fail 'existing filesystem cannot be mounted'
        [ -f /mnt/opt/hexagon/installed ] || fail 'incomplete installation; rebuild disk explicitly to retry'
        umount /mnt
        exec /init normal-boot
    fi
    echo 'HEXAGON_SETUP: formatting private Linux disk'
    mkfs.ext4 -F -m 0 /dev/vda || fail 'format failed'
    mount /dev/vda /mnt || fail 'mount failed'
    echo 'HEXAGON_SETUP: extracting Tuxee'
    tar -xzf /dev/vdb -C /mnt || fail 'root filesystem extraction failed'
    mkdir -p /mnt/opt/hexagon /mnt/etc /mnt/var/lib/tuxee
    cp /bin/busybox /mnt/opt/hexagon/busybox
    cp /hexagon/guest-init /mnt/opt/hexagon/init
    cp /hexagon/seed.env /mnt/opt/hexagon/seed.env || fail 'credentials seed missing'
    chmod 700 /mnt/opt/hexagon /mnt/opt/hexagon/init
    chmod 600 /mnt/opt/hexagon/seed.env
    . /hexagon/seed.env
    printf 'root:%s\n' "$LOGIN_PASSWORD" | chroot /mnt /usr/sbin/chpasswd || fail 'account initialization failed'
    unset LOGIN_PASSWORD
    printf '{"httpPort":80,"httpsPort":0,"state":"/var/lib/tuxee","acme":"off","pam":"login"}\n' > /mnt/etc/hexagon-tuxee.json
    touch /mnt/opt/hexagon/installed
    sync
else
    e2fsck -fp /dev/vda
    code=$?; [ "$code" -le 1 ] || fail 'filesystem check failed'
    resize2fs /dev/vda || fail 'filesystem resize failed'
    mount /dev/vda /mnt || fail 'mount failed'
    [ -f /mnt/opt/hexagon/installed ] || fail 'incomplete installation; disk preserved'
fi
mkdir -p /mnt/dev /mnt/proc /mnt/sys /mnt/run
mount --move /dev /mnt/dev
mount --move /proc /mnt/proc
mount --move /sys /mnt/sys
exec switch_root /mnt /opt/hexagon/busybox sh /opt/hexagon/init
