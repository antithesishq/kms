"""Direct gRPC calls to one core's service endpoint, for result RPCs that take only a
RequestId. kms-core-client has no command for some of them (GetUserDecryptionResult), and
the ones it has always ask every core and verify the result, which a driver doesn't need.

Requests are hand-encoded protobuf: RequestId is message { string request_id = 1; }. The
response bytes are not decoded; only the status code matters to a driver.
"""
import re

import grpc

from helper_common import CLIENT_DIR, pick

SERVICE = "/kms_service.v1.CoreServiceEndpoint/"


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


def request_id_message(request_id):
    data = request_id.encode()
    assert len(data) < 128  # one-byte varint length
    return b"\x0a" + bytes([len(data)]) + data


def call_with_request_id(address, method, request_id, timeout):
    """Call method on the core at address. Returns "ok" or "error=<gRPC status code>"."""
    with grpc.insecure_channel(address) as channel:
        rpc = channel.unary_unary(SERVICE + method)
        try:
            rpc(request_id_message(request_id), timeout=timeout)
            return "ok"
        except grpc.RpcError as e:
            return f"error={e.code().name}"
