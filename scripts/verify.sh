#!/usr/bin/env bash
# End-to-end checks run from the host against the running lab.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
USER_PASSWORD="${USER_PASSWORD:-Lab-User-Passw0rd!}"
export USER_PASSWORD

pass=0
fail=0

run_client() {
    docker compose exec -T -e USER_PASSWORD client bash -c "$1"
}

ssh_as() {
    # usage: ssh_as <user> <password> <remote command>
    # printf %q escapes each value so it survives the extra shell layer inside the container.
    run_client "sshpass -p $(printf '%q' "$2") ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=10 \
        $(printf '%q' "$1@localhost") $(printf '%q' "$3")"
}

sudo_cmd="echo $(printf '%q' "$USER_PASSWORD") | sudo -S -k true"

check() {
    # usage: check "description" <command...>   (succeeds when the command succeeds)
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS  $desc"
        pass=$((pass + 1))
    else
        echo "FAIL  $desc"
        fail=$((fail + 1))
    fi
}

check_not() {
    # usage: check_not "description" <command...>  (succeeds when the command FAILS)
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL  $desc"
        fail=$((fail + 1))
    else
        echo "PASS  $desc"
        pass=$((pass + 1))
    fi
}

echo "== Domain join =="
check "computer account keytab exists" run_client "klist -k /etc/krb5.keytab | grep -qi 'CLIENT[$]@LAB.EXAMPLE'"
check "SSSD answers for the domain" run_client "sssctl domain-status lab.example"

echo "== Identity (NSS) =="
check "alice resolves via getent" run_client "getent passwd alice"
check "alice is in linux-admins" run_client "id -nG alice | tr ' ' '\\n' | grep -qx linux-admins"
check "bob is not in linux-admins" run_client "! (id -nG bob | tr ' ' '\\n' | grep -qx linux-admins)"
check "group linux-users resolves" run_client "getent group linux-users"

echo "== Authentication and access control (PAM over SSH) =="
check "alice logs in with the right password" ssh_as alice "$USER_PASSWORD" "whoami"
check "bob logs in with the right password" ssh_as bob "$USER_PASSWORD" "whoami"
check_not "alice is rejected with a wrong password" ssh_as alice "wrong-password" "whoami"
check_not "carol is denied (not in linux-users)" ssh_as carol "$USER_PASSWORD" "whoami"
check "home directory was created for alice" run_client "test -d /home/alice"

echo "== Privilege (sudo via AD group) =="
check "alice can sudo" ssh_as alice "$USER_PASSWORD" "$sudo_cmd"
check_not "bob cannot sudo" ssh_as bob "$USER_PASSWORD" "$sudo_cmd"

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
