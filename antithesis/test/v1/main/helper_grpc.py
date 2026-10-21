"""Direct gRPC calls to one core's service port, for RPCs whose request a driver can build by
hand: those that take only a RequestId or nothing, and the meta-store status queries.
kms-core-client has no command for some of them (GetUserDecryptionResult, the
MetaStoreStatusService), and the ones it has always ask every core and verify the result,
which a driver doesn't need.

Requests are hand-encoded protobuf (pb_string, pb_varint): RequestId is message { string
request_id = 1; }, Empty is no bytes. Responses are not decoded, except the request IDs a
ListRequests response names (pending_request_ids).
"""
import re

import grpc

from helper_common import CLIENT_DIR, pick

SERVICE = "/kms_service.v1.CoreServiceEndpoint/"
METASTORE_SERVICE = "/metastore_status.v1.MetaStoreStatusService/"


def core_addresses():
    """[(party_id, "host:port")] of the four cores, from the pod's config.toml."""
    with open(f"{CLIENT_DIR}/config.toml") as f:
        blocks = f.read().split("[[cores]]")[1:]
    cores = []
    for b in blocks:
        party = re.search(r"(?m)^party_id *= *(\d+)", b)
        address = re.search(r'(?m)^address *= *"([^"]+)"', b)
        cores.append((int(party.group(1)), address.group(1)))
    return cores


def pick_core():
    return pick(core_addresses())


def varint(n):
    """Protobuf varint; a negative int32 is sign-extended to 64 bits, as protobuf does."""
    n &= (1 << 64) - 1
    out = b""
    while True:
        out += bytes([n & 0x7F | (0x80 if n > 0x7F else 0)])
        n >>= 7
        if not n:
            return out


def pb_string(field, text):
    data = text.encode()
    return varint(field << 3 | 2) + varint(len(data)) + data


def pb_varint(field, n):
    return varint(field << 3) + varint(n)


def request_id_message(request_id):
    return pb_string(1, request_id)


def call(address, path, payload, timeout):
    """Call the RPC at path ("/package.Service/Method") on the core at address with the
    encoded request payload. Returns "ok" or "error=<gRPC status code>"."""
    with grpc.insecure_channel(address) as channel:
        rpc = channel.unary_unary(path)
        try:
            rpc(payload, timeout=timeout)
            return "ok"
        except grpc.RpcError as e:
            return f"error={e.code().name}"


def call_for_response(address, path, payload, timeout):
    """Like call, but returns (outcome, response bytes or None)."""
    with grpc.insecure_channel(address) as channel:
        rpc = channel.unary_unary(path)
        try:
            return "ok", rpc(payload, timeout=timeout)
        except grpc.RpcError as e:
            return f"error={e.code().name}", None


def read_varint(data, i):
    n = shift = 0
    while True:
        b = data[i]
        n |= (b & 0x7F) << shift
        i, shift = i + 1, shift + 7
        if not b & 0x80:
            return n, i


def fields(data):
    """(field number, wire type, value) of a protobuf message; value is an int or bytes."""
    i = 0
    while i < len(data):
        key, i = read_varint(data, i)
        wire = key & 7
        if wire == 0:
            value, i = read_varint(data, i)
        elif wire == 2:
            size, i = read_varint(data, i)
            value, i = data[i:i + size], i + size
        else:
            return  # no other wire types in these messages
        yield key >> 3, wire, value


def pending_request_ids(address, store, timeout=20):
    """IDs of the requests in a meta store (MetaStoreType, e.g. 4 = CRS_GENERATION) that the
    core at address reports as PROCESSING: ListRequestsResponse { repeated RequestStatusInfo
    requests = 1; }, RequestStatusInfo { string request_id = 1; ... }."""
    outcome, resp = call_for_response(address, METASTORE_SERVICE + "ListRequests",
                                      pb_varint(1, store) + pb_varint(2, 0), timeout)
    if resp is None:
        return []
    return [v2.decode() for f, w, v in fields(resp) if f == 1 and w == 2
            for f2, w2, v2 in fields(v) if f2 == 1 and w2 == 2]


def call_with_request_id(address, method, request_id, timeout):
    """Call a CoreServiceEndpoint method that takes a RequestId on the core at address."""
    return call(address, SERVICE + method, request_id_message(request_id), timeout)
