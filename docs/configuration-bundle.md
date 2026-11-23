# Configuration Bundle: Phase 1 & Phase 2 Deliverable
**Project:** Private Network Service Platform  
**Team Namespace:** `goodgoys` (`app.goodgoys.test` / `api.goodgoys.test`)  
**Network Subnet:** `10.7.0.0/19`

---

## 1. Network Environment Reference (`infra/env.sh`)

Every command and configuration file in this bundle derives from these active host IP assignments:

```sh
export team="goodgoys"
export node_1="10.7.31.27"    # Mac 1: Primary DNS Server
export node_2="10.7.21.198"   # Mac 2: Primary Edge / Nginx Reverse Proxy
export node_3="10.7.19.226"   # Mac 3: Backend Server A / Backup DNS / Standby Edge
export node_4="10.7.12.199"   # Mac 4: Backend Server B / Verification Client
```

---

## 2. DNS Configurations (`dnsmasq`)

### 2.1 Primary DNS Server (Mac 1 — Phase 1 & Phase 2 Extension B / E)
**File location:** `config/dnsmasq.conf` (on Mac 1 - `10.7.31.27`)

```text
no-resolv

# Phase 1 & Baseline: Route client traffic to Primary Edge (Mac 2)
address=/app.goodgoys.test/10.7.21.198
address=/api.goodgoys.test/10.7.21.198

# Phase 2 Extension B & E: Visible TTL for controlled migration
local-ttl=10

# Bind only to localhost and Mac 1 LAN interface
listen-address=127.0.0.1,10.7.31.27
interface=en0
bind-interfaces
```

**Launch command:**
```sh
sudo dnsmasq --no-daemon --conf-file=config/dnsmasq.conf
# Or via Makefile:
make dnsmasq-run
```

**Cutover to Standby Edge (Phase 2 Extension E):**
```sh
# Dynamically point address records to Mac 3 (10.7.19.226) and reload:
make dnsmasq-cutover-mac3
```

---

### 2.2 Backup DNS Resolver (Mac 3 — Phase 2 Extension A)
**File location:** `config/backup-dnsmasq.conf` (on Mac 3 - `10.7.19.226`)

```text
no-resolv

# Identical authoritative mapping
address=/app.goodgoys.test/10.7.21.198
address=/api.goodgoys.test/10.7.21.198

local-ttl=30

# Listen on localhost and Mac 3 LAN interface
listen-address=127.0.0.1,10.7.19.226
interface=en0
bind-interfaces
```

**Launch command:**
```sh
sudo dnsmasq --no-daemon --conf-file=config/backup-dnsmasq.conf
# Or via Makefile:
make backup-dnsmasq-run
```

---

## 3. Nginx Reverse Proxy Configurations

### 3.1 Primary Edge Proxy (Mac 2 — Phase 1 Baseline)
**File location:** `config/nginx-phase1.conf`

```nginx
events {}

http {
    upstream backends {
        server 10.7.19.226:3001;
        server 10.7.12.199:3002;
    }

    server {
        listen 443 ssl;
        server_name app.goodgoys.test;

        ssl_certificate     "/Users/pushpendraaa/Desktop/cn-project/app.goodgoys.test.pem";
        ssl_certificate_key "/Users/pushpendraaa/Desktop/cn-project/app.goodgoys.test-key.pem";

        location / {
            proxy_pass http://backends;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
```

---

### 3.2 Hardened Edge Proxy (Mac 2 — Phase 2 Extension D: High Availability Failover)
**File location:** `config/nginx.conf` (Active on Mac 2 - `10.7.21.198`)

Adds proactive error interception and failover timeouts so traffic skips failed backends transparently:

```nginx
events {}

http {
    upstream backends {
        server 10.7.19.226:3001 max_fails=1 fail_timeout=5s;
        server 10.7.12.199:3002 max_fails=1 fail_timeout=5s;
    }

    server {
        listen 443 ssl;
        server_name app.goodgoys.test;

        ssl_certificate     "/Users/pushpendraaa/Desktop/cn-project/app.goodgoys.test.pem";
        ssl_certificate_key "/Users/pushpendraaa/Desktop/cn-project/app.goodgoys.test-key.pem";

        location / {
            proxy_pass http://backends;
            
            # Phase 2 High Availability Failover Directives
            proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
            proxy_next_upstream_timeout 5s;
            proxy_next_upstream_tries 2;

            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
```

**Management commands on Mac 2:**
```sh
make nginx-test      # Validate syntax
make nginx-start     # Start daemon
make nginx-reload    # Hot reload after upstream/certificate change
make nginx-stop      # Shutdown daemon
```

---

### 3.3 Standby Edge Proxy (Mac 3 — Phase 2 Extension E: Edge Migration)
**File location:** `config/standby-nginx.conf` (on Mac 3 - `10.7.19.226`)

```nginx
events {}

http {
    upstream backends {
        server 10.7.19.226:3001 max_fails=1 fail_timeout=5s;
        server 10.7.12.199:3002 max_fails=1 fail_timeout=5s;
    }

    server {
        listen 443 ssl;
        server_name app.goodgoys.test;

        ssl_certificate     "/Users/aniketpathak/cn-project/app.goodgoys.test.pem";
        ssl_certificate_key "/Users/aniketpathak/cn-project/app.goodgoys.test-key.pem";

        location / {
            proxy_pass http://backends;
            proxy_next_upstream error timeout http_500 http_502 http_503;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
```

**Management commands on Mac 3:**
```sh
make standby-nginx-test
make standby-nginx-start
make standby-nginx-stop
```

---

## 4. TLS Certificate Setup Notes

### 4.1 Certificate Authority (CA) Generation with `mkcert`
To guarantee trusted TLS without bypassing certificate verification (`no -k flag` requirement):

1. **Install `mkcert` on the certificate generation machine:**
   ```sh
   brew install mkcert
   mkcert -install
   ```
   *(This creates a local Root CA and places it into macOS Keychain under System Certificates).*

2. **Generate the project wildcard/domain certificates:**
   ```sh
   mkcert -cert-file app.goodgoys.test.pem -key-file app.goodgoys.test-key.pem \
     app.goodgoys.test api.goodgoys.test 10.7.21.198 10.7.19.226
   ```

3. **Distribute Root CA to all Team Macs (Mac 1, 2, 3, 4):**
   - Export Root CA:
     ```sh
     cp "$(mkcert -CAROOT)/rootCA.pem" ./rootCA.pem
     ```
   - Import Root CA into client macOS trust store:
     ```sh
     sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain rootCA.pem
     ```

4. **Verification via OpenSSL:**
   ```sh
   openssl s_client -connect 10.7.21.198:443 -servername app.goodgoys.test -CAfile rootCA.pem
   ```
   *Expected Output:* `Verification: OK`

---

## 5. Backend Launch & Operational Instructions

Both backends run minimal Node.js/Express HTTP microservices binding to all LAN interfaces (`0.0.0.0`).

### 5.1 Backend A (Mac 3 - `10.7.19.226`)
- **Port:** `3001`
- **Identity Header:** `X-Backend: A`
- **Cache Endpoint:** `GET /` returns `Cache-Control: public, max-age=60` and `ETag: "backend-a-v1"`
- **Status Endpoint:** `GET /api/status` returns `{"backend":"A","status":"ok"}`

**Launch command:**
```sh
cd /Users/aniketpathak/cn-project
node backend_a/server.js
# Or via Makefile:
make backend-a
```

### 5.2 Backend B (Mac 4 - `10.7.12.199`)
- **Port:** `3002`
- **Identity Header:** `X-Backend: B`
- **Cache Endpoint:** `GET /` returns `Cache-Control: public, max-age=60` and `ETag: "backend-b-v1"`
- **Status Endpoint:** `GET /api/status` returns `{"backend":"B","status":"ok"}`

**Launch command:**
```sh
cd /path/to/cn-project
node backend_b/server.js
# Or via Makefile:
make backend-b
```

---

## 6. Firewall & Service Isolation Rules (`pf`) (Phase 2 Extension C)

To enforce strict network boundaries, backends accept traffic **only** from the Edge Proxy (`10.7.21.198`), rejecting direct client probes.

### 6.1 Packet Filter Rule File
**File created dynamically at:** `/tmp/pf_backend_a.conf` on Mac 3

```text
# Rule 1: Allow connections originating from the Edge Reverse Proxy (Mac 2)
pass in quick proto tcp from 10.7.21.198 to any port 3001

# Rule 2: Block all other incoming TCP connections to the backend port
block in proto tcp to any port 3001
```

### 6.2 Firewall Activation & Teardown Instructions
- **Activate isolation on Mac 3:**
  ```sh
  make firewall-isolate-backend-a
  # (Executes: sudo pfctl -ef /tmp/pf_backend_a.conf)
  ```
- **Verify Isolation:**
  - Direct probe from client (Mac 4) $\to$ `curl -m 3 http://10.7.19.226:3001/api/status` $\to$ **Hangs / Connection Timed Out**.
  - Proxied request through Edge $\to$ `curl https://app.goodgoys.test/api/status` $\to$ **HTTP 200 OK**.
- **Restore / Teardown:**
  ```sh
  make firewall-disable
  # (Executes: sudo pfctl -d)
  ```
