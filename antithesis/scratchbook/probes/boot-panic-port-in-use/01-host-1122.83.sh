# Probe 1: Timeline A, input_hash -6620762927361152219, vtime 1122.8279770489316, on the host.
# What holds local port 50100 (hex C3D4) in kms-core-2's pod network namespace, 45 ms before the bind.
echo "== $(hostname) $(date -u +%T) uptime=$(cut -d' ' -f1 /proc/uptime) kernel=$(uname -r)"
echo "== tools: $(for t in ss netstat nsenter ps awk sed grep tr crictl; do command -v $t >/dev/null 2>&1 && printf '%s ' $t; done)"
CLK=$(getconf CLK_TCK 2>/dev/null || echo 100)
pinfo() {  # pid -> one line: pid ppid start(s since boot) netns pidns cmdline
  local p=$1 rest st ppid
  rest=$(sed 's/^.*) //' /proc/$p/stat 2>/dev/null) || return
  set -- $rest
  ppid=$2; st=${20}
  echo "pid=$p ppid=$ppid start=$((st / CLK)).$(( (st % CLK) * 100 / CLK )) uid=$(awk '/^Uid:/{print $2}' /proc/$p/status 2>/dev/null) netns=$(readlink /proc/$p/ns/net) pidns=$(readlink /proc/$p/ns/pid) cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-140)"
}
echo "== processes whose environment has HOSTNAME=kms-core-2-core-2 (identity: the pod)"
NS=""; SRV=""
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  h=$(tr '\0' '\n' < $d/environ 2>/dev/null | grep -m1 '^HOSTNAME=')
  [ "$h" = "HOSTNAME=kms-core-2-core-2" ] || continue
  pinfo $p
  NS=$(readlink $d/ns/net)
  case "$(tr '\0' ' ' < $d/cmdline 2>/dev/null)" in kms-server*|*/kms-server*) SRV=$p;; esac
done
echo "== pod netns=$NS kms-server pid=$SRV"
echo "== every process in that netns"
NSPIDS=""
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  [ "$(readlink $d/ns/net 2>/dev/null)" = "$NS" ] || continue
  pinfo $p; NSPIDS="$NSPIDS $p"
done
REF=${SRV:-$(echo $NSPIDS | cut -d' ' -f1)}
echo "== port range in pod netns (via nsenter if present)"
if command -v nsenter >/dev/null 2>&1 && [ -n "$REF" ]; then
  nsenter -t $REF -n cat /proc/sys/net/ipv4/ip_local_port_range /proc/sys/net/ipv4/ip_local_reserved_ports /proc/sys/net/ipv4/tcp_tw_reuse 2>&1
fi
echo "host netns range: $(cat /proc/sys/net/ipv4/ip_local_port_range)"
echo "== TCP table of the pod netns (/proc/$REF/net/tcp and tcp6)"
cat /proc/$REF/net/tcp 2>&1 | head -300
cat /proc/$REF/net/tcp6 2>&1 | head -100
echo "== entries with local port C3D4 (50100)"
MATCH=$(cat /proc/$REF/net/tcp /proc/$REF/net/tcp6 2>/dev/null | awk '$2 ~ /:C3D4$/')
echo "${MATCH:-<none>}"
INODES=$(echo "$MATCH" | awk 'NF {print $10}')
echo "== owners of those sockets (scan of every /proc/*/fd)"
for i in $INODES; do
  [ "$i" = "0" ] && { echo "inode 0 (no owner, e.g. TIME_WAIT)"; continue; }
  found=""
  for f in /proc/[0-9]*/fd/*; do
    [ "$(readlink $f 2>/dev/null)" = "socket:[$i]" ] || continue
    p=${f#/proc/}; p=${p%%/*}; echo "inode $i owned via $f"; pinfo $p; found=1
  done
  [ -n "$found" ] || echo "inode $i: no owning fd found"
done
echo "== LISTEN sockets in pod netns"
cat /proc/$REF/net/tcp /proc/$REF/net/tcp6 2>/dev/null | awk '$4 == "0A"'
echo "== done"
