# VSS feature workload

## Feature

VSS (verifiable secret sharing) is in `core/threshold-execution/src/large_execution/vss.rs`.
Every party deals a batch of secrets at the same time.
At the end, each party holds one share per dealer and secret.
A dealer that the protocol throws out contributes the zero sharing.
VSS runs in four synchronous rounds:

| Round | Channel | What happens | Sets it decides |
|---|---|---|---|
| 1 | private | The dealer sends each party a row `F(X, a_i)`, a column `F(a_i, Y)` and random pads. | none |
| 2 | broadcast | Each party publishes padded values of the cells it shares with every other party. | corrupt (a malformed broadcast) |
| 3 | broadcast, only if a pair disagrees | The dealer, Pi and Pj publish the disputed cell. A party that disagrees with the dealer is unhappy. | potentially unhappy triples, unhappy per dealer, corrupt (more than t unhappy, missing answers) |
| 4 | broadcast, only if a party is unhappy | The dealer publishes the row of each unhappy party. The other happy parties vote with their columns. | voters, corrupt (2t or fewer votes, malformed rows) |

Callers in production: PRSS setup (`small_execution/prss.rs:318`) at every epoch creation, and coinflip (`large_execution/coinflip.rs:85`).
Both combine the shares of all dealers, so an inconsistent sharing or a disagreement about the corrupt set breaks the combined value.

Status: done. The harness tests the code as it is on branch `antithesis-poc-vss-claude`.

## Harness

The harness is `antithesis/vss-harness`, binary `vss-harness`.
It is a self-driving workload: one process runs one VSS session after another, with every party in the process.

- **Network.** The local network of the test runtime, in sync mode, with a 3 s round timeout (`VSS_ROUND_TIMEOUT_MS`).
  VSS waits for every message of a round or for the deadline, so the arrival order inside a round has no effect.
- **Honest parties.** They run the production `SecureVss`.
  For a batch of one secret, they sometimes call `Vss::execute`, as coinflip does.
- **Liars.** At most t parties run `FuzzedVss`, in `malicious_execution/large_execution/fuzzed_vss.rs`.
  At every send, it asks a `VssDecisions` source what to send.
  The harness draws these decisions from Antithesis randomness (`antithesis/vss-harness/src/decisions.rs`).
- **Observer.** A feature-gated hook (`vss_observer`, `large_execution/vss_observer.rs`) reports the sets of each honest party: the corrupt set after rounds 2, 3 and 4; the triples and unhappy sets of round 3; and the voters, yes voters and verdict of each round-4 vote.
- **Session menu.** (n, t) comes from {(4,1), (5,1), (7,2), (8,2), (10,3), (13,4)}, with n = 4 weighted double.
  The batch size is 1, 2, or the PRSS batch size `ceil(binom(n,t)/(n-t))`, capped at 20.
  The ring is Z64 or Z128.
  The number of liars is t (3 times out of 5), a random number in 1..=t, or 0.
  Each secret is zero, one, or a random ring element.
- **Swarm profile.** Each liar draws a deviation probability per decision point from {0, 0.05, 0.3, 0.9, 1}.
  Leaving the protocol has its own lower rates.
  With probability 1/3, a point keeps only one deviation, so the liar repeats one coherent lie.
  Otherwise each deviation is dropped with probability 1/4.

### Decision points of the liar

| Round | Point | Choices |
|---|---|---|
| 1 | `deal(receiver)` | honest, second table, shifted row, shifted column, row or column that matches up to t other receivers, wrong degree, wrong length, silent |
| 2, 3, 4 | `participation(round)` | send, malformed (Bot), drop |
| 2 | `claim(dealer, party, column)` | honest, lie, follow what was dealt (own dealing only) |
| 3 | `dealer_answer(pi, pj)` | truth, side with Pi, side with Pj, random, short batch, omit |
| 3 | `party_answer(dealer, other, as_pi)` | honest, repeat the round-2 claim, random, short batch, omit |
| 3 | `extra_answers()` | entries for triples that are not the liar's disputes |
| 4 | `dealer_row(unhappy_party)` | true row, dealt row, second-table row, majority row, random, wrong degree, zero row, short batch, wrong type, omit |
| 4 | `unrequested_row(party)` | none, or any dealer row for a party that is not unhappy |
| 4 | `vote(dealer, unhappy_party)` | honest, random, wrong type, omit |
| all | `lie_scope()` | lie on all secrets of the batch, or on one |

The liar keeps the bookkeeping of the honest protocol.
A session never adds its own role to its corrupt set (`base_session.rs:165`), so the liar checks for itself when the honest parties treat it as corrupt, and stops then.

## Properties

The invariants assume at most t liars and no honest-to-honest timeout.
With `custom.pause_fault_injector=true`, Antithesis injects no faults.
A timeout would make a slow honest party look like a silent liar, which is more than t faulty parties.

| Property | Type | Why this type |
|---|---|---|
| VSS: every honest party completes the VSS with one share per dealer and secret | Always | Liveness and output shape. A panic of an honest party counts as a failure. |
| VSS: no honest party times out waiting for another honest party | Always | Health of the "no faults" precondition. If it fails, the round timeout is too short or a party hangs. |
| VSS: honest parties agree on the corrupt set | Always | Coinflip and PRSS zero the corrupt dealers. Two views give two different combined values. |
| VSS: no honest party is marked corrupt | Always | Set soundness: only liars belong in the corrupt set. |
| VSS: every honest party reports rounds 2, 3 and 4 to the observer | Always | Harness check: without it, the set properties check nothing. |
| VSS: honest parties compute the same disputed triples and unhappy sets | Always | The sets come from broadcast data, so every honest party must compute the same ones. |
| VSS: honest parties count the same round-4 votes | Always | As above, for voters, yes voters and verdicts. |
| VSS: every disputed triple involves a liar | Always | Two honest parties never disagree about an honest dealer's table. |
| VSS: an honest party is unhappy only with a lying dealer | Always | Set soundness for the unhappy sets. |
| VSS: an honest party takes a share from round 4 only for a dealer it is unhappy with | Always | The comment at the end of round 4 in `vss.rs`: the set of repaired parties is the unhappy set. |
| VSS: honest voters vote for an honest dealer | Always | An honest dealer always survives round 4. |
| VSS: each dealing gives the honest parties shares on one polynomial of degree at most t | Always | The shape guarantee of VSS, for every dealer, lying or not. It leaves out a dealing that an unrequested round-4 row changed, because the round-4 property already reports it, so other causes stay visible. |
| VSS: the honest parties' shares of an honest dealer open to its secret | Always | Correctness for honest dealers. |

Reach claims (`Sometimes`): sessions with t liars, rounds 3 and 4, lying dealers thrown out in round 3 and in round 4, a lying dealer that keeps an unhappy honest party and survives, repaired shares from a lying dealer, a deviating liar that is not caught, a lying dealer whose accepted sharing opens to another value, a liar or a corrupt party counted as a voter, and a corrupt party counted as a yes vote (the accepted deviation below).
Every non-honest choice of every decision point also has a reach claim.

## Faults

The properties are about protocol logic.
VSS waits for the whole round, so network timing inside a round has no effect, and faults would only make honest parties look faulty.
The runs use `custom.pause_fault_injector=true`.
The combination of malice and faults belongs to a run of the full KMS with one malicious core.

## Findings

### Round 4 takes unrequested rows (found 2026-10-28)

At the end of round 4 (`vss.rs`, the loop after the comment "NOTE THAT IF I AM IN UNHAPPY"), each party takes its share from the dealer's round-4 broadcast whenever that broadcast holds a polynomial entry under its name.
The code does not check that the party is in the dealer's unhappy set.
`round_4_fix_conflicts` checks degree, length and votes only for the entries of unhappy parties.
So a lying dealer that survives round 3 can add an entry for any happy party, and that party's share changes to the dealer's choice.

- Effect: the honest shares of the dealing no longer lie on one polynomial of degree t, and the dealer is not thrown out.
  Coinflip and PRSS then combine inconsistent shares.
- Crash variant: an entry with fewer polynomials than the batch size gives that party a short share vector.
  `Vss::execute` checks the length only for dealer 0 and then indexes `vs[0]`; PRSS setup indexes `s[i]`.
  Either can panic an honest core during epoch creation.
- Trigger at n = 4, t = 1 with one liar and no faults: the liar makes one party unhappy, so round 4 runs, and repairs it honestly.
  It also adds a row for a happy party.
  A liar can also make itself unhappy with an honest dealer, so round 4 runs and nobody checks its own message.
- Proof: `fuzzed_vss::tests::unrequested_round_4_rows_do_not_change_honest_shares` asserts the correct behavior and fails on the current code.
  It is `#[ignore]`d with the reason.
  A local harness run found the same failure without help: n = 5, t = 1, liar 3, three honest parties took rows from dealer 3 without being unhappy, and both secrets of that dealing were inconsistent.
- Probable fix: take the round-4 row only if `unhappy_vec[role_sender]` contains the party.

An adversarial review of the first version of the harness found this bug.
Its main point: the first liar sent only the entries that the honest code sends, so the code that reads the broadcasts never saw an unexpected entry.
The decision points `unrequested_row`, `extra_answers`, and the short-batch and wrong-type choices close that gap.

The bug fits Nikita's description: a set has more members than it should, and the polynomial shape property fails.
His run (`f5b8e9c19e35571be11b1815f93f5a5a-64-4`) used only the strategies of `malicious_vss.rs`, which never add an entry.
Without Zama's fix, it is not certain that this is the same bug.

### No party compares its own row and column (found 2026-10-28)

In round 2, a party computes no value for the cell it shares with itself (`generate_verification_value` puts a default there), and `find_potential_conflicts_received_challenges` skips the pair ("No need to compare with itself").
So no party checks that its row and its column agree at its own point.
Round 4 checks only the row of an unhappy party against the columns of the happy parties.

- Attack at n = 4, t = 1, one liar dealer L, no faults:
  - L gives P2 the row `F(X, a2) + c * (X - a3)`, which still matches P3's column, and deals honestly to P3 and P4.
  - L claims in round 2 what P2 holds, so the only dispute is between P2's row and P4's column.
  - L sides with P2 in round 3, so only P4 is unhappy. That is not more than t, and L survives round 3.
  - L repairs P4 with its true row in round 4, which both voters accept.
- Effect: P2's share is `F(0, a2) - c * a3`, so the honest shares are not on one line, and L is not thrown out.
  Unlike the first finding, it needs no unrequested entry.
  For t >= 2 it needs coordinated liars, because the row matches only t columns.
- Proof: `fuzzed_vss::tests::row_matching_t_columns_keeps_honest_shares_consistent` asserts the correct behavior and fails on the current code.
  It is `#[ignore]`d with the reason.
- Probable fix: each party checks `F_i(a_i) == G_i(a_i)` after round 1 and treats a mismatch as a dispute with the dealer.
  We do not know if the NIST specification has this check; the code leaves it out on purpose.
- The fresh-context review of the harness found it (finding B1). The liar got the `PartialRow` and `PartialColumn` deals for it.

### The reliable broadcast loses agreement against one malicious sender (found 2026-10-28)

`SyncReliableBroadcast` (`communication/broadcast.rs`) decides a sender's value when the value has at least n - t votes in the party's own vote count.
A party votes in vote round r once it counts t + r votes, and the last round only receives.
Votes are not relayed, so a malicious sender that sends its echo and its votes to some parties only can make honest parties count different totals.

- Attack at n = 4, t = 1, one liar sender L, no faults:
  - Send round: A to P2 and P3, B to P4.
  - Echo round: an echo of A to P2 only. P2 counts n - t echoes and votes; P3 and P4 count 2 and do not.
  - First vote round: a vote for A to P3 only. P3 counts t + 1 = 2 votes (P2 and L) and votes.
  - Last vote round: a vote for A to P2 and P3.
  - P2 and P3 count 3 votes and output A. P4 counts 2 votes (P2 and P3) and outputs Bot.
- Effect: P4 adds L to its corrupt set (`broadcast_w_corrupt_set_update`) and P2 and P3 do not.
  Every protocol that broadcasts (VSS rounds 2 to 4, PRSS, resharing) then runs with different corrupt sets on different honest parties.
  In VSS, the honest parties compute different disputed triples, and some of them run a round-3 or round-4 broadcast that the others skip.
- Proof: `communication::broadcast::tests::selective_echo_and_votes_do_not_split_the_honest_outputs` sends these messages by hand and fails on the current code, with outputs `[A, A, Bot]`.
  It is `#[ignore]`d with the reason.
- How the harness found it: run `b419aa6c596af5bdf1dd6787c110e29c-64-4` failed "honest parties compute the same disputed triples and unhappy sets" 127 times and "no honest party times out waiting for another honest party" 123 times.
  In the first counterexample (n = 7, t = 2, liars 1 and 7), three honest parties output Bot for liar 1's round-2 broadcast and two output its value.
  The liars run the honest broadcast. The selective delivery came from round-1 silence: the local test network delivers a message of a later round early (`threshold-networking/src/local.rs`, `receive`), so a party that missed a round-1 message from a liar reads the liar's next messages one round early.
  The production gRPC network delivers only messages tagged with the current round (`sending_service/session.rs:210`), but a malicious peer chooses its round tags, so a real liar can send the same pattern on purpose.

### A corrupt voter's missing message can count as a yes vote

The round-4 voter list leaves out unhappy parties, Pi and the dealer, but not corrupt parties.
A corrupt voter has no message, so it counts as zeros.
A dealer that broadcasts a row that is zero at that voter's point gets its vote.
With at most t liars, this gives no more power than a voter in the coalition, so it is not exploitable without faults.
The reach claim "a party marked corrupt before round 4 counts as a yes vote" reports it.
It was an invariant first, but it fails on every run with a zero row, so the review turned it into a reach claim.

## Iteration history

| Date | Run | Change | Result |
|---|---|---|---|
| 2026-10-28 | local, 30 sessions | First version | No violations. 35 of 37 reach claims fired. |
| 2026-10-28 | local, 40 sessions | The liar chooses which entries to send in rounds 3 and 4 | The round-4 membership property, the shape property and the corrupt-voter property fail. |
| 2026-10-28 | Antithesis `6693ef26e151bc9c12d2c1dfffca935c-64-4`, 30 min | First launch | Incomplete after 2 minutes: the harness image was not in the registry (error 4001). `snouty launch` pushes only the config image. |
| 2026-10-28 | Antithesis `b419aa6c596af5bdf1dd6787c110e29c-64-4`, 30 min, turbo | Same build, image pushed | Failing: round-4 membership (1900 counterexamples), shape (1514), completion (1185, with honest panics at `vss.rs:69`), corrupt yes vote (598), disputed-triple agreement (127), honest timeouts (123). Passing: corrupt-set agreement, no honest party corrupt, unhappy only with liars, triples involve a liar, honest voters vote for honest dealers, honest dealers' secrets. Every reach claim fired. The agreement and timeout failures led to the broadcast finding. |
| 2026-10-28 | local, 60 sessions | Review fixes: corrupt-voter invariant becomes a reach claim, the vacuous voter check is removed, the shape check leaves out dealings with unrequested rows; partial-row deals | The round-4 membership property fails twice. The second finding is not reached in 60 sessions. |
| 2026-10-28 | local, 300 sessions | Coherent liar profile (one target, claim what was dealt, defend the deviating party, honest elsewhere) | The second finding is still not reached: the target deal was diluted over 8 deviations. |
| 2026-10-28 | local, 200 sessions | The coherent profile deals only second-table, shifted and partial dealings | The shape property fails twice at n = 4, t = 1 with no unrequested rows: the harness reaches the second finding without help. |
| 2026-10-28 | Antithesis `23469bb8c254e48a3c55dee11646eb58-64-4`, 30 min, turbo | Review fixes, partial deals, coherent profile, round-2 corrupt sets in the agreement details | Failing: shape (2053; every sampled counterexample is n = 4, t = 1, one liar, its own dealing, no unrequested rows, so the second finding), completion (1497; panics at `vss.rs:69` and short share vectors, the first finding), round-4 membership (the first finding), honest timeouts (46; sampled ones are n = 7, t = 2, two honest parties waiting on three others, the desync of the broadcast finding). Passing: every set-soundness and agreement property. Every reach claim fired. |

## Network fidelity

The harness uses the local network of the test runtime.
It differs from the production gRPC network in one way that matters here: a receive accepts the first message of the current round or of a later round.
After a liar is silent to a party in some round, that party reads the liar's later messages one round early.
A real liar can produce the same pattern with its round tags, so this stays inside the adversary model, but the harness cannot choose it on purpose yet.
Honest-to-honest delivery is not affected: honest parties send every round, in order.

## Next steps

- Give the liars a broadcast that they control: send, echo and vote to chosen parties only. Today the broadcast finding comes up only by accident, through round-1 silence.
- Apply the three probable fixes on a separate branch and rerun. The three findings fail most sessions with liars, so they can hide other bugs.
- Let liars coordinate (one liar backs another's lie), for t >= 2.

## Open questions

- Is the unrequested-row bug the one that Zama fixed? A diff of Zama's fix would answer this.
- The liars choose independently. A coalition that coordinates (for example, a lying receiver that backs a lying dealer's side) is not modeled yet.
- The broadcast layer runs honestly for liars. The strategies of `malicious_broadcast.rs` could replace it: sends to some parties only, equivocation, false echoes and votes, a drop in the middle of a broadcast.
- The timeout list (`TIMEOUTS` in `session.rs`) is not keyed by session. A late log line from an aborted task could count against the next session. The receiver of such a line is a liar in practice, so the filter drops it.
- The corrupt-voter reach claim uses the corrupt set at the end of round 3. It misses parties that the round-4 broadcast marks corrupt.
