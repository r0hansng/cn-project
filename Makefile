.PHONY: ping-all dnsmasq-config dnsmasq-run

COUNT ?= 3

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

dnsmasq-config:
	. infra/env.sh; \
	: "$${team:?Set team in infra/env.sh}"; \
	: "$${node_2:?Set node_2 in infra/env.sh}"; \
	printf '%s\n' \
		"no-resolv" \
		"address=/app.$${team}.test/$${node_2}" \
		"address=/api.$${team}.test/$${node_2}" \
		"" \
		"listen-address=127.0.0.1,$${node_1}" \
		"interface=en0" > config/dnsmasq.conf

dnsmasq-run: 
	sudo dnsmasq --no-daemon --conf-file=config/dnsmasq.conf