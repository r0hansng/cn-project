# Network Configuration & Node Inventory

| Machine | Role (Phase 1 & Phase 2) | IPv4 Address | Subnet Mask / Prefix | Default Gateway | Active Interface | MAC Address |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Mac 1** | Primary DNS Server + Client | `10.7.31.27` | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `1a:a5:8c:a8:3b:a6` |
| **Mac 2** | Edge Reverse Proxy + Load Balancer | `10.7.21.198` | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `3e:c2:a2:46:dd:cb` |
| **Mac 3** | Backend A + Backup DNS + Standby Edge | `10.7.19.226` | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `76:5a:63:ab:7f:fc` |
| **Mac 4** | Backend B + Test Client | `10.7.12.199` | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `be:e1:09:82:87:5b` |

---

## Service & Port Allocation

| Machine | Role | Services Running | Protocol / Ports |
| :--- | :--- | :--- | :--- |
| **Mac 1** | Primary DNS | `dnsmasq` (`local-ttl=10`) | UDP/TCP `53` |
| **Mac 2** | Primary Edge | Nginx (TLS termination + HA upstream balancing) | TCP `443` |
| **Mac 3** | Backend A / Secondary DNS / Standby Edge | Node.js Express Backend A, `dnsmasq` backup, Standby Nginx, `pf` firewall | TCP `3001` (Backend)<br/>UDP `53` (Backup DNS)<br/>TCP `443` (Standby Edge) |
| **Mac 4** | Backend B / Verification Client | Node.js Express Backend B, `curl`, `dig`, Wireshark / `tcpdump` | TCP `3002` (Backend)<br/>Ephemeral client ports |
