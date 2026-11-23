.PHONY: help ping-all \
        dnsmasq-config dnsmasq-run dnsmasq-reload dnsmasq-set-ttl dnsmasq-cutover-mac3 dnsmasq-cutover-mac2 \
        backup-dnsmasq-config backup-dnsmasq-run \
        nginx-test nginx-start nginx-reload nginx-stop \
        standby-nginx-test standby-nginx-start standby-nginx-stop \
        backend-a backend-b \
        firewall-isolate-backend-a firewall-disable \
        demo-p1 demo-lb demo-cache demo-backup-dns demo-cutover-watch dns-flush

COUNT ?= 3
TTL ?= 10

help:
	@echo "=== Computer Networks Project Automation Targets ==="
	@echo ""
	@echo "--- 1. Connectivity ---"
	@echo "  make ping-all NODE=1            Ping all other nodes from current node"
	@echo ""
	@echo "--- 2. Primary DNS (Mac 1) ---"
	@echo "  make dnsmasq-config             Generate config/dnsmasq.conf pointing to Mac 2"
	@echo "  make dnsmasq-run                Run primary dnsmasq in foreground"
	@echo "  make dnsmasq-reload             Reload dnsmasq daemon (SIGHUP)"
	@echo "  make dnsmasq-set-ttl TTL=10     Update TTL in config/dnsmasq.conf and reload"
	@echo "  make dnsmasq-cutover-mac3       Point DNS to Standby Edge (Mac 3) for Ext E"
	@echo "  make dnsmasq-cutover-mac2       Point DNS back to Primary Edge (Mac 2)"
	@echo ""
	@echo "--- 3. Backup DNS (Mac 3 - Ext A) ---"
	@echo "  make backup-dnsmasq-config      Generate config/backup-dnsmasq.conf on Mac 3"
	@echo "  make backup-dnsmasq-run         Run backup dnsmasq on Mac 3"
	@echo ""
	@echo "--- 4. Edge Nginx (Mac 2 & Standby Mac 3) ---"
	@echo "  make nginx-test                 Test syntax of config/nginx.conf"
	@echo "  make nginx-start                Start primary Nginx on Mac 2"
	@echo "  make nginx-reload               Reload primary Nginx on Mac 2"
	@echo "  make nginx-stop                 Stop primary Nginx"
	@echo "  make standby-nginx-test         Test syntax of config/standby-nginx.conf on Mac 3"
	@echo "  make standby-nginx-start        Start standby Nginx on Mac 3"
	@echo "  make standby-nginx-stop         Stop standby Nginx on Mac 3"
	@echo ""
	@echo "--- 5. Backends & Firewall Isolation (Mac 3 & Mac 4) ---"
	@echo "  make backend-a                  Start Backend A (port 3001) on Mac 3"
	@echo "  make backend-b                  Start Backend B (port 3002) on Mac 4"
	@echo "  make firewall-isolate-backend-a Block all except Mac 2 on port 3001 (Ext C)"
	@echo "  make firewall-disable           Disable pf firewall rules"
	@echo ""
	@echo "--- 6. Client Demonstrations & Verification ---"
	@echo "  make demo-p1                    Demonstrate Phase 1 DNS -> HTTPS -> Backend flow"
	@echo "  make demo-lb                    Show 10 requests alternating across Backends A & B"
	@echo "  make demo-cache                 Verify Cache-Control and ETag headers"
	@echo "  make demo-backup-dns            Demonstrate Backup DNS resolution (Ext A)"
	@echo "  make demo-cutover-watch         Live stream Edge IP resolution during cutover (Ext E)"
	@echo "  make dns-flush                  Flush local macOS resolver cache (Ext B)"

# ==========================================
# 1. Connectivity
# ==========================================
ping-all:
	. infra/env.sh; \
	: "$${NODE:?Usage: make ping-all NODE=1}"; \
	case "$(NODE)" in 1|2|3|4) ;; *) echo "NODE must be 1, 2, 3, or 4"; exit 1 ;; esac; \
	i=1; \
	for ip in "$$node_1" "$$node_2" "$$node_3" "$$node_4"; do \
		if [ "$$i" -ne "$(NODE)" ]; then \
			ping -c $(COUNT) "$$ip"; \
		fi; \
		i=$$((i + 1)); \
	done

# ==========================================
# 2. Primary DNS (Mac 1)
# ==========================================
dnsmasq-config:
	. infra/env.sh; \
	: "$${team:?Set team in infra/env.sh}"; \
	: "$${node_1:?Set node_1 in infra/env.sh}"; \
	: "$${node_2:?Set node_2 in infra/env.sh}"; \
	printf '%s\n' \
		"no-resolv" \
		"address=/app.$${team}.test/$${node_2}" \
		"address=/api.$${team}.test/$${node_2}" \
		"" \
		"local-ttl=$(TTL)" \
		"" \
		"listen-address=127.0.0.1,$${node_1}" \
		"interface=en0" > config/dnsmasq.conf; \
	echo "Generated config/dnsmasq.conf pointing to Mac 2 ($$node_2) with TTL=$(TTL)s"

dnsmasq-run:
	sudo dnsmasq --no-daemon --conf-file=config/dnsmasq.conf

dnsmasq-reload:
	sudo killall -HUP dnsmasq || true

dnsmasq-set-ttl:
	sed -i '' 's/^local-ttl=.*/local-ttl=$(TTL)/' config/dnsmasq.conf; \
	sudo killall -HUP dnsmasq || true; \
	echo "Updated config/dnsmasq.conf TTL to $(TTL)s and reloaded dnsmasq"

dnsmasq-cutover-mac3:
	. infra/env.sh; \
	sed -i '' "s|address=/app\.$${team}\.test/.*|address=/app\.$${team}\.test/$${node_3}|" config/dnsmasq.conf; \
	sed -i '' "s|address=/api\.$${team}\.test/.*|address=/api\.$${team}\.test/$${node_3}|" config/dnsmasq.conf; \
	sudo killall -HUP dnsmasq || true; \
	echo "DNS migrated to Standby Edge Mac 3 ($$node_3)"

dnsmasq-cutover-mac2:
	. infra/env.sh; \
	sed -i '' "s|address=/app\.$${team}\.test/.*|address=/app\.$${team}\.test/$${node_2}|" config/dnsmasq.conf; \
	sed -i '' "s|address=/api\.$${team}\.test/.*|address=/api\.$${team}\.test/$${node_2}|" config/dnsmasq.conf; \
	sudo killall -HUP dnsmasq || true; \
	echo "DNS restored to Primary Edge Mac 2 ($$node_2)"

# ==========================================
# 3. Backup DNS (Mac 3)
# ==========================================
backup-dnsmasq-config:
	. infra/env.sh; \
	: "$${team:?Set team in infra/env.sh}"; \
	: "$${node_2:?Set node_2 in infra/env.sh}"; \
	: "$${node_3:?Set node_3 in infra/env.sh}"; \
	printf '%s\n' \
		"no-resolv" \
		"address=/app.$${team}.test/$${node_2}" \
		"address=/api.$${team}.test/$${node_2}" \
		"" \
		"local-ttl=$(TTL)" \
		"" \
		"listen-address=127.0.0.1,$${node_3}" \
		"interface=en0" > config/backup-dnsmasq.conf; \
	echo "Generated config/backup-dnsmasq.conf for Mac 3 ($$node_3)"

backup-dnsmasq-run:
	sudo dnsmasq --no-daemon --conf-file=config/backup-dnsmasq.conf

# ==========================================
# 4. Edge Nginx (Mac 2 & Mac 3)
# ==========================================
nginx-test:
	sudo nginx -t -c "$$(pwd)/config/nginx.conf"

nginx-start:
	sudo nginx -c "$$(pwd)/config/nginx.conf"

nginx-reload:
	sudo nginx -s reload

nginx-stop:
	sudo nginx -s stop || true

standby-nginx-test:
	sudo nginx -t -c "$$(pwd)/config/standby-nginx.conf"

standby-nginx-start:
	sudo nginx -c "$$(pwd)/config/standby-nginx.conf"

standby-nginx-stop:
	sudo nginx -s stop || true

# ==========================================
# 5. Backends & Firewall Isolation
# ==========================================
backend-a:
	node backend_a/server.js

backend-b:
	node backend_b/server.js

firewall-isolate-backend-a:
	. infra/env.sh; \
	printf "pass in quick proto tcp from %s to any port 3001\nblock in proto tcp to any port 3001\n" "$$node_2" > /tmp/pf_backend_a.conf; \
	sudo pfctl -ef /tmp/pf_backend_a.conf; \
	echo "PF rules applied on Mac 3: Port 3001 only accessible from Mac 2 ($$node_2)"

firewall-disable:
	sudo pfctl -d || true; \
	echo "PF firewall disabled"

# ==========================================
# 6. Client Demonstrations & Verification
# ==========================================
demo-p1:
	. infra/env.sh; \
	echo "=== 1. DNS Resolution ==="; \
	dig @$$node_1 app.$$team.test +short; \
	echo "=== 2. HTTPS Response ==="; \
	curl -sS https://app.$$team.test/api/status; echo ""; \
	echo "=== 3. Backend Identity Header ==="; \
	curl -sS -I https://app.$$team.test/api/status | grep -i X-Backend

demo-lb:
	. infra/env.sh; \
	echo "Running 10 requests to show load balancing between Backends A & B..."; \
	for i in {1..10}; do \
		curl -sS -I https://app.$$team.test/api/status | grep -i X-Backend; \
	done

demo-cache:
	. infra/env.sh; \
	echo "Checking Cache-Control and ETag headers on root endpoint..."; \
	curl -i https://app.$$team.test/ | grep -E -i "cache-control|etag|http"

demo-backup-dns:
	. infra/env.sh; \
	echo "--- Testing Primary DNS ($$node_1) ---"; \
	dig @$$node_1 app.$$team.test +short || echo "Primary DNS unreachable"; \
	echo "--- Testing Backup DNS ($$node_3) ---"; \
	dig @$$node_3 app.$$team.test +short

demo-cutover-watch:
	. infra/env.sh; \
	echo "Monitoring Edge IP resolution and responses (Ctrl+C to exit)..."; \
	while true; do \
		RESOLVED_IP=$$(dig @$$node_1 app.$$team.test +short | tail -n1); \
		STATUS=$$(curl -k -s -w "%{http_code}" --resolve app.$$team.test:443:$$RESOLVED_IP https://app.$$team.test/api/status -o /dev/null); \
		BACKEND=$$(curl -k -s -D - --resolve app.$$team.test:443:$$RESOLVED_IP https://app.$$team.test/api/status | grep -i "X-Backend:" | tr -d '\r'); \
		echo "$$(date +%T) | Edge IP: $$RESOLVED_IP (HTTP $$STATUS) | $$BACKEND"; \
		sleep 2; \
	done

dns-flush:
	sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; echo "Client DNS cache flushed successfully"
