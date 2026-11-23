# Private Network Service Platform

![Status](https://img.shields.io/badge/status-phase%201%20%26%202%20complete-2ea44f?style=for-the-badge)
![Network](https://img.shields.io/badge/network-private%20LAN%20%2F%20Wi--Fi-0969da?style=for-the-badge)
![DNS](https://img.shields.io/badge/DNS-dnsmasq%20(primary%20%2B%20backup)-orange?style=for-the-badge)
![Edge](https://img.shields.io/badge/edge-nginx%20(TLS%201.3%20%2B%20HA)-009639?style=for-the-badge)
![Runtime](https://img.shields.io/badge/runtime-Node.js%20Express-339933?style=for-the-badge)
![Security](https://img.shields.io/badge/security-packet%20filter%20(pf)-blueviolet?style=for-the-badge)

**Computer Networks Course Project**  
**Team Namespace:** `goodgoys` (`app.goodgoys.test` / `api.goodgoys.test`)  
**Deployment:** 4 macOS Physical Laptops (No Cloud Dependencies)

This project implements a private local network platform spanning four physical macOS machines: authoritative primary and backup DNS resolvers (`dnsmasq`), high-availability HTTPS reverse proxying and load balancing (Nginx with TLS 1.3), isolated Node.js REST microservices, zero-trust packet filtering (`pf`), and live DNS-based edge cutover.

---

## Team Members & Node Allocation

| Node | Team Member | Enrollment Number | Physical Role | Active IP (`infra/env.sh`) | Services / Ports |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Mac 1** | Rohan Singh | `2401010391` | Primary DNS + Test Client | `10.7.31.27` | `dnsmasq` (`local-ttl=10`), UDP/TCP `53` |
| **Mac 2** | Pushpendra Singh | `2401010361` | Edge Proxy + Load Balancer | `10.7.21.198` | Nginx TLS (`proxy_next_upstream`), TCP `443` |
| **Mac 3** | Aniket Pathak | `2401020088` | Backend A + Backup DNS + Standby Edge | `10.7.19.226` | Node.js (`3001`), `dnsmasq` backup (`53`), Standby Nginx (`443`), `pf` |
| **Mac 4** | Kapil Karan Mathur | `2401010209` | Backend B + Test Client | `10.7.12.199` | Node.js (`3002`), `curl`, `dig`, Wireshark |

---

## Architecture

```text
                       [ Primary DNS: Mac 1 (10.7.31.27:53) ]
                       [ Backup DNS:  Mac 3 (10.7.19.226:53) ]
                                          ^
                                          | DNS Query (app.goodgoys.test)
                                          v
[ Client Node (Mac 4) ] --------> [ Edge Nginx: Mac 2 (10.7.21.198:443) ]
                                  (Standby Edge: Mac 3 - Cutover Target)
                                          |
                      +-------------------+-------------------+
                      | (Round-Robin / Failover)               |
                      v                                       v
         [ Backend A: Mac 3 (3001) ]             [ Backend B: Mac 4 (3002) ]
         (Firewall: Only Mac 2 allowed)          (Firewall: Only Mac 2 allowed)
```

---

## Repository Structure

- `backend_a/`: Node.js Express REST microservice A (`port 3001`, `X-Backend: A`)
- `backend_b/`: Node.js Express REST microservice B (`port 3002`, `X-Backend: B`)
- `config/`: Configuration files for `dnsmasq`, backup `dnsmasq`, Nginx, and Standby Nginx
- `infra/env.sh`: Centralized environment variables (`team`, `node_1`, `node_2`, `node_3`, `node_4`)
- `docs/`: Comprehensive project deliverables:
  - `docs/architecture.md`: Full topology, protocol mapping, and request sequence diagrams
  - `docs/configuration-bundle.md`: Complete bundle of all DNS, Nginx, TLS, and PF configurations
  - `docs/phase2-final-report.md`: Phase 2 resilience findings, test results, and learning summaries
  - `docs/network-configuration.md`: Node IP and MAC inventory
- `Makefile`: Complete project automation for Phase 1 and Phase 2 demonstrations

---

## Quick Start & Verification

### 1. Environment & Connectivity Check
Load the environment and verify connectivity from any node:
```sh
source infra/env.sh
make ping-all NODE=1 COUNT=3
```

### 2. Start Services
- **Primary DNS (Mac 1):**
  ```sh
  make dnsmasq-config
  make dnsmasq-run
  ```
- **Edge Reverse Proxy (Mac 2):**
  ```sh
  make nginx-test
  make nginx-start
  ```
- **Backend A (Mac 3) & Backend B (Mac 4):**
  ```sh
  make backend-a   # on Mac 3 (port 3001)
  make backend-b   # on Mac 4 (port 3002)
  ```

---

## Demonstration & Evaluation Commands (Makefile)

### Phase 1 Baseline Demonstration
From the client terminal (e.g. Mac 4 or Mac 1):
```sh
make demo-p1     # Runs DNS lookup, curls HTTPS endpoint, prints X-Backend
make demo-lb     # Runs 10 requests showing round-robin alternation between A & B
make demo-cache  # Displays Cache-Control: max-age=60 and ETag headers
```

### Phase 2 Hardened Extensions Demonstration
- **Extension A (Backup DNS Resolver):**
  - Mac 3: `make backup-dnsmasq-config && make backup-dnsmasq-run`
  - Client: `make demo-backup-dns` (queries both primary and backup resolvers)
- **Extension B (DNS TTL & Cache Flush):**
  - Mac 1: `make dnsmasq-set-ttl TTL=10`
  - Client: `make dns-flush` (clears local `mDNSResponder` cache immediately)
- **Extension C (Service Isolation / Firewall):**
  - Mac 3: `make firewall-isolate-backend-a` (blocks all client traffic to port 3001 except from Mac 2)
  - Mac 3: `make firewall-disable` (restores default access)
- **Extension D (High-Availability Backend Failover):**
  - Configured with `proxy_next_upstream` in `config/nginx.conf`.
  - Kill Backend A (`Ctrl+C` on Mac 3) $\to$ client requests continue 100% to Backend B without 502 errors.
- **Extension E (Zero-Downtime Edge Cutover):**
  - Mac 3: `make standby-nginx-start`
  - Client: `make demo-cutover-watch` (streams live Edge IP resolution)
  - Mac 1: `make dnsmasq-cutover-mac3` (flips DNS A record to Mac 3 live)
  - Mac 1: `make dnsmasq-cutover-mac2` (restores DNS A record to Mac 2)

Type `make help` for a quick list of all available commands.
