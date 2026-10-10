#!/usr/bin/env python3
# Send one forged message to every address of a mailcow host and report whether a stranger can spoof the domain.
import socket
import sys

if len(sys.argv) != 3:
    sys.exit(f"usage: {sys.argv[0]} <mailcow-hostname> <existing-mailbox>")
host, mailbox = sys.argv[1:3]
domain = mailbox.split("@")[1]


def probe(addr):
    sock = socket.create_connection((addr, 25), timeout=30)
    rd = sock.makefile("rb")

    def reply():
        lines = []
        while True:
            raw = rd.readline()
            if not raw:
                sys.exit("server closed the connection before replying")
            line = raw.decode(errors="replace").rstrip()
            lines.append(line)
            if len(line) < 4 or line[3] == " ":
                break
        print("<", "\n< ".join(lines))
        return lines[-1][:3]

    def cmd(text):
        print(">", text)
        sock.sendall((text + "\r\n").encode())
        return reply()

    reply()
    cmd("EHLO spoof-probe.invalid")
    accepted = False
    cmd(f"MAIL FROM:<{mailbox}>")
    if cmd(f"RCPT TO:<{mailbox}>").startswith("2") and cmd("DATA").startswith("3"):
        body = (f"From: {mailbox}\r\nTo: {mailbox}\r\nSubject: spoof-test\r\n\r\n"
                f"If you can read this, anyone can send mail as @{domain} without logging in.\r\n.\r\n")
        sock.sendall(body.encode())
        accepted = reply().startswith("2")
    cmd("QUIT")
    print("\nspoofed sender accepted:", "YES" if accepted else "rejected")
    return accepted


addrs = sorted({info[4][0] for info in socket.getaddrinfo(host, 25, proto=socket.IPPROTO_TCP)})
bad = False
for addr in addrs:
    print(f"=== {host} via {addr}")
    bad |= probe(addr)
    print()
sys.exit(1 if bad else 0)
