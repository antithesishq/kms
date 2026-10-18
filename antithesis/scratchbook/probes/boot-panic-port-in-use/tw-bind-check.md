# Local check: a TIME-WAIT socket on the service port blocks the listener's bind

Supports the unconfirmed finding [A restarting core sometimes can't bind its service port](../../../../zama-kms/speedrun-report.md#boot-panic-port-in-use).
This checks a kernel behaviour on this VM (Linux 6.12); it is not an observation from the Antithesis run.

**Question.** Can a closed outgoing connection that happened to get local port 50100 make
`bind(0.0.0.0:50100)` fail for a later server process in the same network namespace, even though
tokio's `TcpListener::bind` sets `SO_REUSEADDR`?

**Script:** [tw_bind_test2.py](tw_bind_test2.py), run as
`unshare -rn sh -c 'ip link set lo up && echo "50100 50101" > /proc/sys/net/ipv4/ip_local_port_range && python3 -I tw_bind_test2.py'`.
The narrowed ephemeral range only makes the kernel's choice of 50100 certain instead of
occasional. The client socket sets no options, like curl or an HTTP client library.

```text
50100	50101
client local port: 50100
State     Recv-Q Send-Q Local Address:Port  Peer Address:PortProcess
LISTEN    0      0          127.0.0.1:9000       0.0.0.0:*
TIME-WAIT 0      0          127.0.0.1:50100    127.0.0.1:9000
bind 0.0.0.0:50100 failed: EADDRINUSE
bind 0.0.0.0:50100 failed: EADDRINUSE
```

[tw_bind_test.py](tw_bind_test.py) gives the same result with the client port chosen explicitly.

**What this shows.** The side that closes a TCP connection first keeps a TIME-WAIT socket on its
local port for 60 s. The client socket never set `SO_REUSEADDR`, so Linux refuses a new listener on
that port during that time, `SO_REUSEADDR` on the listener notwithstanding. A pod that makes
outgoing connections to MinIO before kms-server binds 50100 can therefore hit "Could not bind to
0.0.0.0:50100 … AddrInUse" whenever one of those connections got local port 50100. 50100 sits inside
Linux's default ephemeral range (32768–60999), and the failure clears within about a minute. That
fits the run: the port stays taken for 34–43 s across restarts and is free again about 76 s after
the stop.

**Not shown.** That this is what held the port in the run. No socket listing exists for the failing
moment.
