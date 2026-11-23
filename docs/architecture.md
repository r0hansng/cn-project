# Architecture Document: Private Network Service Platform
**Course Project: Computer Networks**  
**Team Namespace:** `goodgoys` (`app.goodgoys.test` / `api.goodgoys.test`)  
**Status:** Updated for Phase 2 (Harden, Recover, and Troubleshoot)

---

## 1. Network Topology Diagram

The infrastructure runs entirely on an isolated local area network across up to four physical macOS nodes. Clients access all services through private domain names managed by custom authoritative DNS resolvers.

### 1.1 Phase 1 Baseline Topology
In Phase 1, Mac 2 acts as the single edge gateway terminating TLS and balancing requests between Backend A and Backend B:

```mermaid
flowchart TD
    subgraph LAN ["Private Wi-Fi / LAN Segment (Subnet 10.7.0.0/19)"]
        direction TB

        ClientNode["Client Machine (Mac 4 / Mac 1)<br/>Ephemeral Ports"]

        subgraph DNS_Layer ["DNS Service Layer"]
            Mac1["Mac 1: Primary DNS Server<br/>IP: 10.7.31.27<br/>Daemon: dnsmasq (UDP/TCP Port 53)"]
        end

        subgraph Edge_Layer ["Edge / Ingress Layer"]
            Mac2["Mac 2: Edge Reverse Proxy & Load Balancer<br/>IP: 10.7.21.198<br/>Daemon: nginx + OpenSSL (TCP Port 443)"]
        end

        subgraph Backend_Layer ["Application Backend Layer"]
            Mac3["Mac 3: Backend Server A<br/>IP: 10.7.19.226<br/>Service: Node.js / Express (TCP Port 3001)"]
            Mac4["Mac 4: Backend Server B<br/>IP: 10.7.12.199<br/>Service: Node.js / Express (TCP Port 3002)"]
        end

        ClientNode -->|"1. DNS Query (UDP:53)"| Mac1
        Mac1 -.->|"2. Resolve app.goodgoys.test -> 10.7.21.198"| ClientNode
        ClientNode -->|"3. HTTPS (TLS 1.3 / TCP:443)"| Mac2
        Mac2 -->|"4. Round-Robin HTTP Proxy (Port 3001)"| Mac3
        Mac2 -->|"4. Round-Robin HTTP Proxy (Port 3002)"| Mac4
    end
```

---

### 1.2 Phase 2 Hardened Topology (Resilience, Isolation & Failover)
In Phase 2, the network adds a **secondary backup DNS resolver**, **packet-filter service isolation**, an **Nginx upstream health failover**, and a **standby edge proxy** for live DNS migration:

```mermaid
flowchart TD
    subgraph LAN_P2 ["Hardened LAN Topology (Phase 2)"]
        direction TB

        ClientNodeP2["Client Node (Mac 4 / Any)<br/>Configured with Primary & Secondary Resolvers"]

        subgraph HighAvailability_DNS ["Resilient DNS Layer (Ext A & B)"]
            PrimaryDNS["Mac 1: Primary DNS Server<br/>IP: 10.7.31.27:53 (local-ttl=10)"]
            BackupDNS["Mac 3: Backup DNS Server<br/>IP: 10.7.19.226:53 (Standby / Secondary)"]
        end

        subgraph Redundant_Edge ["Edge Migration & Proxy Layer (Ext D & E)"]
            PrimaryEdge["Mac 2: Active Edge Reverse Proxy<br/>IP: 10.7.21.198:443<br/>(Health check: proxy_next_upstream)"]
            StandbyEdge["Mac 3: Standby Edge Reverse Proxy<br/>IP: 10.7.19.226:443<br/>(Target of DNS Cutover Migration)"]
        end

        subgraph Isolated_Backends ["Service Isolation Layer (Ext C: Packet Filter Rules)"]
            direction LR
            FW_A["pf Firewall: Only 10.7.21.198 permitted"] --> BackendA["Mac 3: Backend A<br/>Port 3001"]
            FW_B["pf Firewall: Only 10.7.21.198 permitted"] --> BackendB["Mac 4: Backend B<br/>Port 3002"]
        end

        ClientNodeP2 -->|"DNS Query (Primary)"| PrimaryDNS
        ClientNodeP2 -.->|"Fallback if Primary Fails (Ext A)"| BackupDNS

        ClientNodeP2 -->|"Active HTTPS Route"| PrimaryEdge
        ClientNodeP2 -.->|"Post-Cutover HTTPS Route (Ext E)"| StandbyEdge

        PrimaryEdge -->|"Allowed by PF (Pass Quick)"| FW_A
        PrimaryEdge -->|"Allowed by PF (Pass Quick)"| FW_B

        ClientNodeP2 -.-x|"Direct Access Blocked by PF (Ext C)"| FW_A
        ClientNodeP2 -.-x|"Direct Access Blocked by PF (Ext C)"| FW_B
    end
```

---

## 2. Machine Roles and IP / Service Inventory Table

| Node | Physical Machine | Phase 1 Primary Role | Phase 2 Extended Capabilities | IPv4 Address | Active Ports | Underlying Daemons / Tools | Cloud Infrastructure Analog |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Mac 1** | Primary Infrastructure | Authoritative DNS Server | Primary DNS with configurable TTL (`local-ttl=10`) & DNS Cutover controller | `10.7.31.27` | UDP `53`<br/>TCP `53` | `dnsmasq`, macOS networking | AWS Route 53 / Google Cloud DNS |
| **Mac 2** | Edge Node | Reverse Proxy & Round-Robin Load Balancer | TLS termination, Active failover (`proxy_next_upstream`, `fail_timeout=5s`) | `10.7.21.198` | TCP `443`<br/>TCP `80` (redirect) | Nginx 1.25+, OpenSSL 3.x, macOS PKI | AWS Application Load Balancer (ALB) / Cloudflare Edge |
| **Mac 3** | App Server A | Backend REST Instance A (`X-Backend: A`) | **1.** Backup DNS Resolver (Ext A)<br/>**2.** `pf` Service Isolation (Ext C)<br/>**3.** Standby Edge Proxy (Ext E) | `10.7.19.226` | TCP `3001` (Backend)<br/>UDP `53` (Backup DNS)<br/>TCP `443` (Standby Edge) | Node.js v20+, Express, `dnsmasq`, `pfctl` (BSD Packet Filter) | EC2 Instance A / Standby Multi-AZ Ingress Gateway |
| **Mac 4** | App Server B & Client | Backend REST Instance B (`X-Backend: B`) | Verification Client, Wireshark Packet Sniffer, Automated Failover Tester | `10.7.12.199` | TCP `3002` (Backend)<br/>Ephemeral client ports | Node.js v20+, Express, `curl`, `dig`, Wireshark / `tcpdump` | EC2 Instance B / VPC Test Consumer Client |

---

## 3. End-to-End Request Flow Diagram by Protocol Layer

Every client transaction traverses all five layers of the TCP/IP stack across multiple network boundaries.

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (Mac 4)<br/>App / OS Layer
    participant D as DNS Server (Mac 1)<br/>dnsmasq (:53)
    participant E as Edge Proxy (Mac 2)<br/>nginx TLS (:443)
    participant B as Backend A (Mac 3)<br/>Node.js (:3001)

    Note over C,D: LAYER 5 (Application - DNS) & LAYER 4 (Transport - UDP)
    C->>D: Standard Query: app.goodgoys.test (IN A, UDP Src: 54120 -> Dst: 53)
    D-->>C: Query Response: app.goodgoys.test -> 10.7.21.198 (TTL: 10s)

    Note over C,E: LAYER 4 (Transport - TCP) - Handshake
    C->>E: TCP SYN [Seq=0] (Src: 49832 -> Dst: 443)
    E-->>C: TCP SYN-ACK [Seq=0, Ack=1] (Src: 443 -> Dst: 49832)
    C->>E: TCP ACK [Seq=1, Ack=1] (Src: 49832 -> Dst: 443)

    Note over C,E: LAYER 4/5 (Session & Security - TLS 1.3)
    C->>E: ClientHello (Supported Ciphers, SNI: app.goodgoys.test, Key Share)
    E-->>C: ServerHello, ChangeCipherSpec, Encrypted Certificate, Key Exchange
    C->>E: Finished (Session Handshake Complete)
    Note over C,E: Application Data Encrypted via TLS Session Key

    Note over C,B: LAYER 5 (Application - HTTP/1.1 over TLS)
    C->>E: GET /api/status HTTP/1.1 (Host: app.goodgoys.test)
    
    Note over E,B: Reverse Proxy Upstream Dispatch (Internal LAN)
    E->>B: TCP Handshake + GET /api/status (Host: app.goodgoys.test, X-Forwarded-For)
    B-->>E: HTTP/1.1 200 OK (X-Backend: A, Cache-Control: max-age=60, ETag)
    
    E-->>C: TLS Encrypted Response (HTTP/1.1 200 OK, X-Backend: A)
    Note over C: Client OS caches HTTP payload according to Cache-Control
```

---

## 4. Layer-by-Layer Protocol Mapping Table

| Stack Layer | Protocol | Encapsulation & Packet Identifiers | Concrete Implementation in this System | Observation & Diagnostic Tool |
| :--- | :--- | :--- | :--- | :--- |
| **Layer 5 (Application)** | **DNS** | UDP Payload, Port `53`, A Record mapping name to IPv4 address | `dnsmasq` authoritative mapping for `*.goodgoys.test` | `dig @10.7.31.27 app.goodgoys.test +short` |
| **Layer 5 (Application)** | **HTTP/1.1** | Headers: `Host`, `X-Backend`, `Cache-Control`, `ETag`, Status Code | Express REST endpoints on Backends A & B; proxied by Nginx | `curl -i https://app.goodgoys.test/api/status` |
| **Layer 4 / 5 (Security / Session)** | **TLS 1.3** | Handshake records: `ClientHello`, `ServerHello`, Certificate Exchange, Encrypted Application Data | Nginx TLS termination with RSA/ECDSA cert issued by local CA (`mkcert`) | `openssl s_client -connect 10.7.21.198:443 -servername app.goodgoys.test` |
| **Layer 4 (Transport)** | **TCP & UDP** | TCP 3-way handshake (`SYN`, `SYN-ACK`, `ACK`), Ephemeral client ports (e.g. `51234`), Destination ports `53`, `443`, `3001`, `3002` | Kernel TCP/IP stack; socket pairs `(SrcIP:SrcPort, DstIP:DstPort)` | Wireshark filter: `tcp.port == 443 \|\| udp.port == 53` |
| **Layer 3 (Network)** | **IPv4** | Source & Destination IP addresses, TTL packet counter, Subnet routing (`10.7.0.0/19`) | LAN private routing across macOS Wi-Fi interfaces (`en0`) | `ping -c 3 10.7.21.198`<br/>`netstat -rn` |
| **Layer 2 (Data Link)** | **Ethernet / 802.11** | Source & Destination MAC addresses (hardware framing) | Physical Wi-Fi frame transfer over local access point | `arp -a`<br/>`tcpdump -e -i en0` |

---

## 5. Phase 2 Hardening Extensions Summary

### 5.1 Extension A: Resilient Secondary DNS
- Primary DNS (`10.7.31.27`) and Secondary DNS (`10.7.19.226`) run identical records.
- If Primary DNS ceases operation, client resolver falls back to Secondary DNS without interrupting application availability.

### 5.2 Extension B: DNS Cache Governance & Controlled Change
- DNS responses are pinned to a short, visible TTL (`local-ttl=10` or `30`).
- Cache retention is observable on client resolvers prior to expiry, and manual cache invalidation is executed with `dscacheutil -flushcache; killall -HUP mDNSResponder`.

### 5.3 Extension C: Service Isolation via Packet Filter (`pf`)
- Backends (`3001`, `3002`) enforce zero-trust boundary rules.
- Rule: `pass in quick proto tcp from 10.7.21.198 to any port 3001` followed by `block in proto tcp to any port 3001`.
- Direct client access to backend instances is dropped at the link/transport layer; all queries must traverse the authenticated TLS edge proxy.

### 5.4 Extension D: Upstream Active Failover
- Nginx upstream definition uses `max_fails=1 fail_timeout=5s` and `proxy_next_upstream error timeout http_502`.
- When Backend A halts, requests route to Backend B transparently with zero client-perceived HTTP 502 errors.

### 5.5 Extension E: Zero-Downtime Edge Migration
- Standby Nginx reverse proxy configured on Mac 3 (`10.7.19.226`).
- Authoritative DNS record modified to switch `app.goodgoys.test` from Mac 2 to Mac 3.
- Transition displays zero dropped requests as client resolvers switch over upon TTL expiration.
