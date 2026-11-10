FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sssd sssd-ad sssd-tools adcli krb5-user libnss-sss libpam-sss \
        libpam-modules openssh-server sudo sshpass dnsutils netcat-openbsd \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# NSS: resolve users and groups through SSSD.
RUN for db in passwd group shadow; do \
        grep -qE "^${db}:.*sss" /etc/nsswitch.conf || sed -i -E "s/^(${db}:.*)$/\1 sss/" /etc/nsswitch.conf; \
    done

# PAM: authenticate through SSSD and create home directories at first login.
RUN pam-auth-update --enable sss mkhomedir --force

COPY krb5.conf /etc/krb5.conf
COPY sssd.conf.tmpl /etc/sssd/sssd.conf.tmpl
COPY lab-sshd.conf /etc/ssh/sshd_config.d/10-lab.conf
COPY lab-sudoers /etc/sudoers.d/linux-admins
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0440 /etc/sudoers.d/linux-admins \
    && chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p /run/sshd

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
