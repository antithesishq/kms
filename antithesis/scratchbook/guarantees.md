# Guarantees: Zama

Written for Zama's KMS engineers. Each row is a promise Zama makes to the clients of the KMS (the
Zama Protocol's gateway and connectors, and through them the dApps and users who decrypt), stated
in plain technical language.
Ranked: faults/concurrency-sensitivity × business impact, with client-checkability as the
tie-breaker. The research behind them is in [system-brief.md](system-brief.md#promises-to-clients).

| Guarantee | Statement | Source | Breaks under | Property slug | Type |
|---|---|---|---|---|---|
| [Guarantee 1](#guarantee-1) | Every public-decryption result a core signs carries exactly the plaintext that was encrypted, whichever single core crashes, restarts or is cut off while the decryption runs (correctness under threshold robustness) | [Zama Protocol litepaper](https://docs.zama.org/protocol/zama-protocol-litepaper): "our MPC protocol is robust, meaning it will give a correct output with up to 1/3 malicious nodes." | crash, restart, partition, race between concurrent requests | `public-decrypt-returns-encrypted-plaintext` | Safety |
| [Guarantee 2](#guarantee-2) | Once faults stop, every core accepts connections again within 600 s, and from then on a new public decryption answered by all four cores succeeds within 300 s, so a core that was killed or cut off has rejoined (availability after recovery, i.e. guaranteed output delivery) | [KMS overview](https://docs.zama.org/protocol/protocol/overview/kms): "It supports guaranteed output delivery even if some nodes are offline or misbehaving."; [kms-server-bin.md](https://github.com/zama-ai/kms/blob/main/docs/guides/kms-server-bin.md): "This allows failing nodes to re-join an existing set of nodes, without running `init` again." Windows inferred: no recovery time is documented, so the decryption window is the deployed MPC `network_timeout` (300 s), and the reconnect bound covers Kubernetes' restart back-off cap (300 s) plus boot ([evidence](properties/recovers-after-faults.md#is-300-s-safe)) | faults stopping after crashes, restarts and partitions | `recovers-after-faults` | Liveness |
| [Guarantee 3](#guarantee-3) | Resharing the key into a new epoch, while decryptions run and faults hit, keeps the same FHE key: decryptions under the new epoch return the encrypted plaintexts and the public key doesn't change, and a reshare that fails leaves the earlier epoch serving (key resharing) | [entry_points.md](https://github.com/zama-ai/kms/blob/main/docs/guides/entry_points.md#key-reshare): "the pseudorandom values that each party hold … change, but with the public key remaining the same"; [ARCHITECTURE.md](../../ai-docs/ARCHITECTURE.md): "A storage failure during resharing rolls the new epoch back on the party that fails." | crash or partition during a reshare, reshare racing decryptions | `reshare-preserves-key` | Safety |
| [Guarantee 4](#guarantee-4) | Every user decryption the client reconstructs from the cores' encrypted shares yields exactly the encrypted plaintext or an error, never a different value, under the same faults (correctness of threshold user decryption) | [trust_model.md](https://github.com/zama-ai/kms/blob/main/docs/explanations/trust_model.md): "up to `t` of the `n` parties may be malicious, and the protocol still protects the secret key and produces correct results." | crash, restart, partition, race | `user-decrypt-returns-encrypted-plaintext` | Safety |
| [Guarantee 5](#guarantee-5) | Re-sending a decryption request under the same request ID, after a timeout, an error or a core restart, is answered as documented: a failed attempt runs again, a pending or finished one is reported as already existing (asynchronous calls) or attached to (synchronous calls), and every result carries the original request's plaintexts (request-ID idempotency) | [trust_model.md](https://github.com/zama-ai/kms/blob/main/docs/explanations/trust_model.md): "If the earlier attempt failed, the core resets the entry and runs the decryption again." … "Synchronous decryption … treats a known ID as a request to attach" | restart (which empties the in-memory request store), timeouts, concurrent retries | `decrypt-request-id-retries` | Safety |

## Notes per guarantee

<a id="guarantee-1"></a>
### Guarantee 1: public decryption returns the encrypted plaintext
- **The check, in one sentence:** the workload encrypts random values it chose, sends the
  public decryption to all four cores, and `Always` every response whose signature verifies
  under that core's published key carries the encrypted value for every ciphertext in the batch.
- **Inherited from:** customer's own.
- **Why it matters to Zama:** public decryption results are published on chain by the gateway,
  where a wrong plaintext can't be undone; the client's majority check doesn't help if the
  honest cores agree on a wrong value.

<a id="guarantee-2"></a>
### Guarantee 2: the cluster serves decryptions again after faults stop
- **The check, in one sentence:** after Antithesis stops injecting faults, a command waits
  for all four cores to accept connections (`Always` within 600 s), then retries a fresh public
  decryption that needs all four cores' responses, and `Always` it succeeds within 300 s; a `Sometimes` records a recovery where the first attempt
  failed and a later one succeeded.
- **Inherited from:** customer's own.
- **Why it matters to Zama:** "guaranteed output delivery" is a headline promise of the Zama
  Protocol; a core that can't rejoin after a restart leaves the cluster one more failure away
  from an outage.

<a id="guarantee-3"></a>
### Guarantee 3: resharing keeps the key
- **The check, in one sentence:** while drivers decrypt, a command reshares the key into a new
  epoch; decryptions under every epoch that reported success `Always` return the encrypted
  plaintexts, the public key read after the reshare `Always` equals the one read before, and
  decryptions under the earlier epoch keep working when a reshare fails.
- **Inherited from:** customer's own.
- **Why it matters to Zama:** resharing is how operators rotate shares after a compromise or a
  lost share; five resharing fixes landed between August and October 2026 ([brief](system-brief.md#hard-problems)).

<a id="guarantee-4"></a>
### Guarantee 4: user decryption returns the encrypted plaintext
- **The check, in one sentence:** the workload user-decrypts values it encrypted, and `Always`
  every plaintext the client reconstructs from the cores' signcrypted shares equals the
  encrypted value.
- **Inherited from:** customer's own.
- **Why it matters to Zama:** user decryption is how a dApp user reads their own balance or
  data; a wrong value (as in the fixed bug where it returned 0) is silently wrong data.

<a id="guarantee-5"></a>
### Guarantee 5: retries under one request ID behave as documented
- **The check, in one sentence:** the workload resends some decryption requests under the same
  request ID (byte-identical, as the connector does), and `Always` each reply is one the
  documentation allows for the earlier attempt's state, and every result carries the original
  plaintexts.
- **Inherited from:** customer's own (the connector relies on it to re-send after a core restart).
- **Why it matters to Zama:** the KMS connector re-sends requests after errors and core
  restarts; an answer outside the documented set strands a request or returns the wrong result.

## Not covered

- **Malicious (Byzantine) parties.** Antithesis injects crashes, restarts, network faults and
  clock jumps, not parties that lie, so the "up to 1/3 malicious" part of Guarantee 1's source is
  checked only for faulty-but-honest parties.
