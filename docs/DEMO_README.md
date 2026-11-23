# Live Demonstration & Evaluation Guide

This guide details the exact sequence of commands to execute during the live evaluation. The steps correspond directly to the **Section 8 Final Demonstration Sequence (11 Steps)** in the project specifications.

---

## Pre-Demo Setup (Start Services on Each Machine)

Run these commands in separate terminals on each assigned machine before calling the evaluator:

| Machine | Role | IP (`infra/env.sh`) | Command to Start Service |
| :--- | :--- | :--- | :--- |
| **Mac 1** | Primary DNS | `10.7.31.27` | `make dnsmasq-run` |
| **Mac 2** | Primary Edge | `10.7.21.198` | `make nginx-start` |
| **Mac 3** | Backend A | `10.7.19.226` | `make backend-a` |
| **Mac 4** | Backend B | `10.7.12.199` | `make backend-b` |

---

## 11-Step Demonstration Sequence

### Step 1: Show Topology and IP/Service Inventory
- **Action:** Open and display the architecture document in a browser or markdown viewer.
- **File:** `docs/architecture-p1-p2.md` (or `docs/network-configuration.md`)
- **Explanation:** Point out the 4 machine roles, IP addresses, listening ports (`53`, `443`, `3001`, `3002`), and the request path from client to edge to backends.

---

### Step 2: Confirm All Machines on the Private LAN
- **Run on any Mac (e.g., Mac 1):**
  ```sh
  make ping-all NODE=1
  ```
- **Expected Result:** 3 successful ping replies from `10.7.21.198`, `10.7.19.226`, and `10.7.12.199` with 0% packet loss.

---

### Step 3: Resolve the Private Domain from a Client
- **Run on Client (Mac 4 or Mac 1):**
  ```sh
  dig @10.7.31.27 app.goodgoys.test +short
  ```
- **Expected Result:**
  ```text
  10.7.21.198
  ```
- **Explanation:** Demonstrates that our custom DNS resolver on Mac 1 maps `app.goodgoys.test` directly to the Edge proxy on Mac 2.

---

### Step 4: Open Service over HTTPS Using the Domain Name
- **Run on Client:**
  ```sh
  curl -v https://app.goodgoys.test/api/status
  ```
- **Expected Result:**
  - TLS 1.3 handshake succeeds with no warnings.
  - Certificate is trusted by the local Root CA (no `-k` flag needed).
  - Returns HTTP 200 with JSON payload: `{"backend":"...","status":"ok"}`.

---

### Step 5: Show Load Balancing Across Both Backends
- **Run on Client:**
  ```sh
  make demo-lb
  ```
- **Expected Result:** 10 consecutive requests showing alternating headers:
  ```text
  X-Backend: A
  X-Backend: B
  X-Backend: A
  X-Backend: B
  ...
  ```

---

### Step 6: Show Wireshark Evidence of DNS, TCP, and TLS
- **Action:** Open Wireshark on the client and load the capture file from `evidence/`.
- **Apply Display Filters:**
  1. `udp.port == 53` $\to$ Show DNS Query for `app.goodgoys.test` and Response with `10.7.21.198`.
  2. `tcp.port == 443` $\to$ Show the TCP 3-way handshake (`[SYN]`, `[SYN, ACK]`, `[ACK]`) before TLS negotiation.
  3. `tls` $\to$ Show `Client Hello`, `Server Hello`, `Certificate`, and subsequent encrypted `Application Data`.

---

### Step 7: Show HTTP Headers and Caching Behavior
- **Run on Client:**

  1. **Show Cache-Control & ETag Headers:**
     ```sh
     make demo-cache
     ```
     *Output:* `Cache-Control: public, max-age=60` and `ETag: "backend-a-v1"`.

  2. **Demonstrate 304 Not Modified (Conditional Request):**
     ```sh
     curl -i -H 'If-None-Match: "backend-a-v1"' https://app.goodgoys.test/
     ```
     *Expected Output:*
     ```text
     HTTP/1.1 304 Not Modified
     ETag: "backend-a-v1"
     Cache-Control: public, max-age=60
     ```
     *(Empty body returned, proving cache validation works).*

---

### Step 8: Fail One Backend and Prove Service Continues
1. **On Mac 3:** Stop Backend A (`Ctrl+C`).
2. **On Client:** Run:
   ```sh
   for i in {1..4}; do curl -sS -I https://app.goodgoys.test/api/status | grep -i X-Backend; done
   ```
   *Expected Result:* All requests succeed and return `X-Backend: B`. Zero `502 Bad Gateway` errors appear (handled by Nginx `proxy_next_upstream`).
3. **On Mac 3:** Restart Backend A:
   ```sh
   make backend-a
   ```
   *(Round-robin resumes across both backends after 5 seconds).*

---

### Step 9: Demonstrate Phase 2 DNS & Resilience (Edge Cutover)
1. **On Mac 3:** Start the standby Nginx instance:
   ```sh
   make standby-nginx-start
   ```
2. **On Client:** Start the live cutover watcher:
   ```sh
   make demo-cutover-watch
   ```
   *(Streams: `Edge IP: 10.7.21.198 | X-Backend: ...`)*
3. **On Mac 1:** Trigger DNS cutover to Mac 3:
   ```sh
   make dnsmasq-cutover-mac3
   ```
4. **Observe on Client:** The output automatically switches to:
   ```text
   Edge IP: 10.7.19.226 | X-Backend: ...
   ```
   *(Zero dropped packets during live migration).*
5. **Restore on Mac 1 after demo:** `make dnsmasq-cutover-mac2`

---

### Step 10: Diagnose Faculty-Injected Fault
When the faculty introduces a configuration fault, execute these 4 commands in order and explain your findings out loud:

```sh
# 1. Test DNS Resolution Layer
dig @10.7.31.27 app.goodgoys.test +short

# 2. Test TCP Transport Layer
nc -zvw3 10.7.21.198 443

# 3. Test TLS Security Layer
openssl s_client -connect 10.7.21.198:443 -servername app.goodgoys.test

# 4. Test Application / Upstream Layer
curl -i https://app.goodgoys.test/api/status
```

- **If Step 1 fails:** DNS issue (`dnsmasq` stopped, wrong port, or invalid address mapping).
- **If Step 2 fails:** Transport/Port issue (Nginx down, wrong port, or `pf` firewall rule blocking traffic).
- **If Step 3 fails:** TLS certificate issue (expired cert, untrusted CA, or SNI mismatch).
- **If Step 4 returns 502:** Upstream backend failure (both Node.js servers stopped or unreachable).

---

### Step 11: Individual Viva Questions & Key Concepts

- **Why does DNS use UDP port 53?**  
  DNS queries are small, single-packet request/response exchanges. UDP avoids the 3-packet handshake overhead of TCP, significantly reducing latency. (TCP 53 is used for zone transfers or responses exceeding 512 bytes).
- **What is the function of the TCP 3-way handshake?**  
  Synchronizes Sequence Numbers (`SYN` $\to$ `SYN-ACK` $\to$ `ACK`), negotiates Maximum Segment Size (MSS), and establishes a full-duplex, reliable connection before application data is exchanged.
- **Why terminate TLS at the reverse proxy (Edge)?**  
  Offloads cryptographic compute overhead from application backends, centralizes certificate management, and allows the proxy to inspect HTTP headers for intelligent routing, caching, and rate limiting.
- **What is the difference between a cache hit, conditional 304, and full request?**  
  - *Fresh Cache Hit:* Client serves cached response directly without contacting server (within `max-age`).
  - *Conditional 304:* Client asks server if resource changed via `If-None-Match`. Server responds `304 Not Modified` with zero body bytes.
  - *Full Request:* Cache expired or invalidated; server generates full HTTP 200 payload.
- **What is the remaining Single Point of Failure (SPOF)?**  
  The Edge proxy on Mac 2. If Mac 2 fails, all traffic halts. In production, this is solved with an Active/Passive proxy pair running VRRP (Keepalived) over a shared Virtual IP (VIP), or Anycast BGP routing across multiple edge servers.
