# Phase 2 Final Report: Harden, Recover, and Troubleshoot
**Course:** Computer Networks Course Project  
**Team Namespace:** `goodgoys` (`app.goodgoys.test` / `api.goodgoys.test`)  
**Network Subnet:** `10.7.0.0/19`  
**Review Area:** Phase 2 Deliverable (Resilience, Isolation, Failover & Troubleshooting)

---

## 1. Executive Summary & What Changed from Phase 1

In Phase 1, our team established a functional private networking baseline: an authoritative DNS service on Mac 1, a single Nginx reverse proxy with TLS termination on Mac 2, and two Node.js HTTP REST backends on Mac 3 and Mac 4 serving requests in a round-robin load-balanced fashion. While this demonstrated end-to-end multi-layer communication, the architecture contained multiple single points of failure (SPOFs), had zero network isolation between backends and clients, and lacked proactive error handling.

In Phase 2, we hardened the platform across all layers of the OSI/TCP-IP stack without introducing external cloud infrastructure:
1. **Resilient DNS Layer (Layer 5/4):** Deployed a redundant secondary authoritative resolver (`dnsmasq`) on Mac 3 and governed resolution lifetimes using explicit DNS Time-To-Live (`local-ttl=10`) parameters.
2. **Service Isolation & Zero-Trust Boundary (Layer 3/4):** Configured macOS Packet Filter (`pf`) rules on application backends, disallowing direct client probes on ports `3001`/`3002` while exclusively permitting ingress traffic from the Edge proxy (`10.7.21.198`).
3. **High-Availability Upstream Failover (Layer 5/4):** Hardened Nginx with active failure detection (`proxy_next_upstream`, `max_fails=1`, `fail_timeout=5s`), eliminating client-facing `502 Bad Gateway` errors during backend outages.
4. **Zero-Downtime Edge Migration:** Implemented a standby Nginx instance on Mac 3 and executed seamless live traffic cutover by mutating DNS records within the bounded TTL window.
5. **Systematic Fault Injection & Diagnostic Framework:** Established a layer-by-layer troubleshooting protocol (DNS $\to$ TCP $\to$ TLS $\to$ Upstream Application) capable of isolating broken network states within seconds.

---

## 2. Resilience Tests and Experimental Results

| Test Scenario | Injected Fault / Action | Observed Network Behavior | Recovery & System Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Extension A:** Primary DNS Failure | Primary `dnsmasq` stopped on Mac 1 (`sudo killall dnsmasq`) | Client OS query times out on `10.7.31.27:53` and falls back to `10.7.19.226:53` | Name resolution succeeds without interruption; `app.goodgoys.test` returns `10.7.21.198`. | **PASS** |
| **Extension B:** DNS TTL & Record Change | Record changed to Mac 3; `local-ttl=10` applied | Client resolver holds old IP (`10.7.21.198`) for exactly 10s, then receives `10.7.19.226`. Flushing via `dscacheutil` immediately invalidates cache. | Proved DNS is a cached directory and demonstrated controlled cutover timing. | **PASS** |
| **Extension C:** Backend Service Isolation | Packet filter (`pf`) enabled on Mac 3: `pass in quick from 10.7.21.198 to :3001; block to :3001` | Direct client probe (`curl http://10.7.19.226:3001`) hangs and times out. Proxied HTTPS request (`curl https://app.goodgoys.test`) returns `200 OK`. | Backend ports are fully shielded from non-proxy clients, eliminating direct perimeter bypass. | **PASS** |
| **Extension D:** Backend Unavailability (HA) | Backend A (`server.js` on Mac 3) abruptly killed during active traffic | Nginx detects upstream socket refusal, invokes `proxy_next_upstream`, and routes request to Backend B in `< 25ms`. Zero 502s returned to client. | Traffic served 100% by Backend B. When Backend A restarts, round-robin automatically resumes after `5s`. | **PASS** |
| **Extension E:** Edge Proxy Migration | Standby Nginx started on Mac 3; DNS A record updated to `10.7.19.226` | Continuous client monitoring shows seamless IP flip from `10.7.21.198` to `10.7.19.226` as TTL expires. All requests receive HTTP 200. | Zero client downtime; edge tier successfully migrated across physical hardware nodes. | **PASS** |

---

## 3. Troubleshooting Findings & Diagnostic Methodology

During Phase 2 implementation, our team identified and resolved key operational challenges across the protocol stack:

1. **DNS Daemon Sockets vs. SIGHUP Signal:**  
   We found that issuing `killall -HUP dnsmasq` does not reload inline `address=/.../` directives on macOS if they are defined directly inside `dnsmasq.conf` rather than an external `hosts` file. Modifying live records during edge migration required explicit daemon restarts or updating secondary configuration targets to guarantee fresh socket binding.
2. **Client-Side OS Resolver Caching vs. Query Tools:**  
   Testing with `dig` directly queries the DNS server port and bypasses the operating system's local resolver cache, whereas `curl` and browsers rely on macOS `mDNSResponder`. We reconciled this discrepancy by demonstrating that `mDNSResponder` strictly honors the `local-ttl` duration or clears immediately upon invoking `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.
3. **BSD Packet Filter (`pf`) Rule Ordering:**  
   Unlike Linux `iptables` where top-to-bottom evaluation can terminate early, macOS `pf` applies the *last matching rule* by default unless the `quick` keyword is specified. To permit the Edge proxy while denying the rest of the LAN, we used `pass in quick proto tcp from 10.7.21.198 to any port 3001` followed by `block in proto tcp to any port 3001`.
4. **Nginx Upstream Error Trapping:**  
   In baseline Phase 1, stopping one backend resulted in intermittent `502 Bad Gateway` errors for 50% of client requests. Injecting `proxy_next_upstream error timeout http_502` and `fail_timeout=5s` into the `http` block allowed Nginx to intercept TCP socket resets (`ECONNREFUSED`) and transparently retry the second upstream server before completing the client HTTP exchange.

---

## 4. Learning Summary (One Paragraph per Extension)

### Extension A: Backup DNS Resolver
Configuring a redundant DNS resolver on Mac 3 underscored that high availability at the application layer is meaningless if the name resolution layer is fragile. We observed how client resolver libraries handle multi-homed DNS configurations, experiencing first-hand how the client transport stack implements retry timeouts before querying secondary resolvers. This directly relates to cloud infrastructure architectures such as AWS Route 53 and Google Cloud DNS, where authoritative nameservers are distributed across distinct IP subnets and anycast clusters to prevent total namespace unreachability.

### Extension B: DNS TTL and Controlled Record Change
Working with explicit DNS TTL configurations revealed the fundamental trade-off between client caching efficiency and administrative agility during records changes. We learned that while longer TTLs minimize network round-trips and reduce query load on authoritative nameservers, they inhibit immediate disaster recovery and service redirection. By enforcing a 10-second TTL and observing client cache behavior, we learned the industry-standard cutover practice: lowering TTL values days ahead of a scheduled migration to ensure clients pull updated records promptly during traffic transition.

### Extension C: Service Isolation (Backend Firewall Rules)
Implementing packet filter rules on our application servers demonstrated the principle of defense-in-depth and zero-trust service isolation. We proved that exposing application service ports directly to an entire subnet creates severe security vulnerabilities, as malicious clients can bypass edge authentication, rate limiting, and TLS termination. Enforcing packet-level filtering using `pfctl` taught us how cloud security groups (such as AWS EC2 Security Groups or VPC Network ACLs) operate at the transport and network boundaries, guaranteeing that backend microservices only accept socket pairs established by trusted reverse proxies.

### Extension D: High-Availability Failover Behavior
Configuring Nginx’s upstream health tracking and failover interception provided a clear understanding of dynamic reverse proxy fault tolerance. We learned how an edge gateway acts as an abstraction barrier between external consumers and internal microservices, hiding backend node crashes and network partition events. By capturing and observing zero-downtime responses when killing a backend instance, we recognized how production application load balancers (such as AWS ALB or HAProxy) perform health checking and upstream retries to achieve high-availability service-level agreements (SLAs).

### Extension E: Controlled Edge Migration (DNS-Based Cutover)
The edge cutover exercise tied together DNS caching, upstream proxying, and multi-node coordination to execute a live migration without packet drop. We observed how traffic naturally drained from the primary edge on Mac 2 to the standby edge on Mac 3 as client DNS cache timers expired. This simulated blue/green cloud deployments and edge CDN cutovers, proving that network architectures can achieve seamless hardware maintenance, datacenter evacuations, or catastrophic edge recovery without modifying application backend code or disrupting active client sessions.

### Extension F: Faculty-Injected Troubleshooting Challenge
Developing our systematic four-tier diagnostic methodology reinforced that network engineering is rooted in disciplined layer isolation rather than random trial-and-error. By strictly probing the stack sequentially—verifying DNS resolution (`dig`), TCP port reachability (`nc`/`ping`), TLS handshake integrity (`openssl s_client`), and finally application HTTP response headers (`curl -v`)—we learned how to pinpoint whether a failure stems from a routing issue, firewall block, stale record, or crashed process in seconds. This structured approach provided deep confidence in our ability to defend and diagnose any network fault injected during live evaluation.
