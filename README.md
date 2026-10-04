# Private Network Service Platform

This project demonstrates a small private network service: `dnsmasq` resolves internal hostnames, Nginx terminates HTTPS and load-balances requests, and two Node.js services provide redundant backends.

## Architecture

```text
Client -> dnsmasq -> app.<team>.test -> Nginx:443 -> Backend A:3001 / Backend B:3002
```

- `backend_a/`: Node.js backend A
- `backend_b/`: Node.js backend B
- `config/`: dnsmasq and Nginx configuration
- `infra/env.sh`: lab hostnames and node addresses
- `docs/`: network design, validation, and evidence notes
- `Makefile`: connectivity and dnsmasq configuration commands

## Prerequisites

- Node.js and npm on the backend hosts
- Nginx with a TLS certificate and key for the configured hostname
- `dnsmasq` on the DNS host
- A shared network between the client, DNS host, edge host, and backend hosts

## Setup

1. Edit `infra/env.sh` with the addresses for your four nodes. Set `team` to the DNS suffix you will use.
2. Install dependencies on each backend host:

	```sh
	cd backend_a && npm install
	cd ../backend_b && npm install
	```

3. Start the backends:

	```sh
	# Host running backend A
	cd backend_a && npm start

	# Host running backend B
	cd backend_b && node server.js
	```

4. Generate the local DNS records and start dnsmasq on the DNS host:

	```sh
	make dnsmasq-config
	make dnsmasq-run
	```

5. Update `config/nginx.conf` with the backend addresses and TLS certificate paths, validate it with `sudo nginx -t`, and start or reload Nginx on the edge host.

6. Configure clients to use the DNS host, then verify the service:

	```sh
	dig app.<team>.test
	curl -v https://app.<team>.test/api/status
	```

## Validation

The backends expose `GET /api/status`, which returns the backend identity and `status: ok`, and `GET /`, which returns cache headers and an `ETag`. The `X-Backend` response header identifies which service handled a request.

## Makefile Usage

Run commands from the project root:

| Command | Purpose |
|---|---|
| `make ping-all NODE=2` | Ping every node except node 2 |
| `make ping-all NODE=2 COUNT=5` | Send 5 packets to every node except node 2 |
| `make dnsmasq-config` | Generate DNS records from `infra/env.sh` |
| `make dnsmasq-run` | Generate the DNS config and start dnsmasq |

`NODE` must be `1`, `2`, `3`, or `4`. The selected node is excluded from the ping test. `COUNT` defaults to `3`.

For example, to skip node 2 and send one packet to the other nodes:

```sh
make ping-all NODE=2 COUNT=1
```

See `docs/report-p1.md` for load-balancing, TLS, failure, and packet-capture validation procedures.
