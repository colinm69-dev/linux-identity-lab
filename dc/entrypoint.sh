#!/usr/bin/env bash
# Provision a Samba AD domain on first start, create demo OUs/users/groups, then run samba.
set -euo pipefail

REALM="${LAB_REALM:?}"
DOMAIN="${LAB_DOMAIN:?}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?}"
USER_PASSWORD="${USER_PASSWORD:?}"
READY_FLAG=/var/lib/samba/.lab-ready
DNS_REALM="${REALM,,}"
BASE_DN="DC=${DNS_REALM//./,DC=}"

if [ ! -f "$READY_FLAG" ]; then
    echo "[dc] First start: provisioning ${REALM}"
    rm -f /etc/samba/smb.conf
    samba-tool domain provision \
        --use-rfc2307 \
        --realm="$REALM" \
        --domain="$DOMAIN" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --adminpass="$ADMIN_PASSWORD" \
        --option="dns forwarder=127.0.0.11"
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

    # Start samba in the background so we can seed demo data, then stop it.
    samba -i &
    SAMBA_PID=$!
    for _ in $(seq 1 60); do
        if smbclient -L localhost -N >/dev/null 2>&1; then break; fi
        sleep 1
    done

    echo "[dc] Seeding demo directory objects"
    samba-tool ou create "OU=People"
    samba-tool ou create "OU=Groups"

    for entry in "alice:Alice:Example" "bob:Bob:Example" "carol:Carol:Example"; do
        IFS=: read -r uname given sur <<<"$entry"
        samba-tool user create "$uname" "$USER_PASSWORD" \
            --given-name="$given" --surname="$sur" \
            --userou="OU=People" \
            --mail-address="${uname}@${DNS_REALM}"
        # Demo accounts never expire so the lab keeps working.
        samba-tool user setexpiry "$uname" --noexpiry
    done

    samba-tool group add linux-users --groupou="OU=Groups"
    samba-tool group add linux-admins --groupou="OU=Groups"
    samba-tool group addmembers linux-users alice,bob
    samba-tool group addmembers linux-admins alice
    # carol exists but is deliberately NOT in linux-users, to demonstrate access control.

    kill "$SAMBA_PID"
    wait "$SAMBA_PID" || true
    touch "$READY_FLAG"
    echo "[dc] Provisioning complete for ${BASE_DN}"
else
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
    echo "[dc] Existing domain found, starting"
fi

exec samba -i
