#!/usr/bin/env bash
# Join the domain on first start, render sssd.conf, then run sshd and sssd.
set -euo pipefail

REALM="${LAB_REALM:?}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?}"
DNS_DOMAIN="${REALM,,}"
BASE_DN="DC=${DNS_DOMAIN//./,DC=}"
DC_FQDN="dc.${DNS_DOMAIN}"

echo "[client] Waiting for the domain controller"
for _ in $(seq 1 60); do
    if getent hosts "$DC_FQDN" >/dev/null 2>&1 && (exec 3<>"/dev/tcp/${DC_FQDN}/389") 2>/dev/null; then
        break
    fi
    sleep 2
done

if ! klist -k /etc/krb5.keytab >/dev/null 2>&1; then
    echo "[client] Joining ${DNS_DOMAIN}"
    printf '%s' "$ADMIN_PASSWORD" | adcli join \
        --stdin-password \
        --domain="$DNS_DOMAIN" \
        --domain-controller="$DC_FQDN" \
        --login-user=Administrator \
        --host-fqdn="client.${DNS_DOMAIN}"
else
    echo "[client] Already joined"
fi

sed "s/__BASE_DN__/${BASE_DN}/" /etc/sssd/sssd.conf.tmpl >/etc/sssd/sssd.conf
chmod 0600 /etc/sssd/sssd.conf

ssh-keygen -A
/usr/sbin/sshd -D -e &

echo "[client] Starting SSSD"
exec sssd -i --logger=stderr
