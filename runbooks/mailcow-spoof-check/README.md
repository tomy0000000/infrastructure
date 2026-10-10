# Mailcow Spoof Check

Checks whether mailcow accepts mail from a stranger who forges a `@tomy.me`
sender. When Docker had `iptables` disabled, every connection arrived through
docker-proxy as the bridge gateway `172.22.1.1`, which is in Postfix's `mynetworks`.
Postfix and rspamd then treated inbound mail as local, skipped SPF, DKIM and DMARC,
and delivered a phishing mail sent as `fake@tomy.me`. Relaying was never open:
`extra.cf` refuses unauthenticated relay for every client, trusted or not.

Run it after touching `/etc/docker/daemon.json`, the host firewall, or the
IPv6 settings in `mailcow.conf`, and after every reboot of the mailcow host.

## What it tests

`probe.py` connects to port 25 of every address of the host as a stranger
with no credentials and sends one message with the given mailbox forged as
sender, addressed to that same mailbox. A healthy server rejects it at end of
`DATA`: rspamd's `SPOOFED_UNAUTH` composite scores 50 for an unauthenticated
client using a mailcow domain with a failing SPF or DMARC result. `250 Ok:
queued` means the client was treated as local and the spoof got through, and
the message lands in that mailbox as proof. Exit code is 1 in that case.

The sender must be a real mailbox. Postfix checks unknown senders with
`reject_unlisted_sender`, which only trusted clients skip, so a made-up sender
is rejected for the wrong reason and proves nothing.

## Run it

From any machine other than the mailcow host, on a network where outbound
port 25 is open (most home and office networks block it, a phone hotspot
usually works):

```
python3 probe.py mailcow.tomy.me github@tomy.me
```

Healthy output ends with, once per address:

```
spoofed sender accepted: rejected
```

Do not run it on the host itself: a connection from the host hairpins through
NAT as the gateway, and a container on another Docker network is masqueraded
as the gateway too. Both are trusted and the test passes for the wrong reason.

## If it fails

Look at `docker compose logs postfix-mailcow | grep 'connect from'` on the
host. The probe should appear with the address of the machine you ran it on.
If it shows as `172.22.1.1`, the port is being served by docker-proxy instead
of NAT. Then check, in this order: `iptables`/`ip6tables` not set to `false`
in `/etc/docker/daemon.json`, `nft list ruleset` listing Docker's `ip nat` and
`ip6 nat` tables with a `DOCKER` chain, and `systemctl is-enabled nftables`
saying `disabled`. Ubuntu's `nftables.service` flushes the whole ruleset when
it stops, so never `systemctl stop nftables` on a running Docker host.
