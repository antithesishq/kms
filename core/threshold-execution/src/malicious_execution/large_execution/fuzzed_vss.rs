//! A malicious VSS party that asks a [`VssDecisions`] source what to send at each decision
//! point of the protocol in [`crate::large_execution::vss`].
//!
//! The other strategies in [`super::malicious_vss`] each hardcode one deviation. This one
//! makes every deviation available at every send, so a test harness that draws the choices at
//! random explores combinations of them across all four rounds. All choices concern values
//! the party sends; the party keeps the bookkeeping of the honest protocol, so its view of
//! the unhappy and corrupt sets matches the honest views.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use async_trait::async_trait;
use itertools::Itertools;

use crate::{
    communication::broadcast::Broadcast,
    large_execution::vss::{
        DoublePoly, MapRoleDoublePoly, Round1VSSOutput, SecureVss, ValueOrPoly, VerificationValues,
        Vss, answer_to_potential_conflicts, find_potential_conflicts_for_all_roles,
        find_real_conflicts, generate_verification_value, round_1, sample_secret_polys,
        verify_round_2_broadcast,
    },
    network_value::BroadcastValue,
    runtime::sessions::base_session::BaseSessionHandles,
};
use algebra::{
    bivariate::BivariatePoly,
    poly::Poly,
    structure_traits::{Ring, RingWithExceptionalSequence},
};
use threshold_types::protocol::ProtocolDescription;
use threshold_types::role::Role;

/// What the party sends to one receiver of its own dealing in round 1.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Deal {
    /// The row and column of the dealer's table.
    Honest,
    /// The row and column of a second table, which shares other secrets.
    OtherTable,
    /// The honest row plus a random constant: the share changes and the column does not.
    ShiftedRow,
    /// The honest column plus a random constant.
    ShiftedColumn,
    /// The honest row plus a random multiple of a polynomial that vanishes at the points of up
    /// to t other receivers. The row still matches their columns and disagrees with the rest.
    PartialRow,
    /// The column version of [`Deal::PartialRow`].
    PartialColumn,
    /// A row of degree t + 1. The receiver rejects the message and uses zeros.
    WrongDegree,
    /// One polynomial pair more than the batch size. The receiver rejects the message.
    WrongLength,
    /// No message.
    Silent,
}

/// How the party takes part in the broadcast of a round.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Participation {
    /// Broadcast the message, with the per-value choices applied.
    Send,
    /// Broadcast a value of the wrong variant, then stop.
    Malformed,
    /// Stop executing VSS before the broadcast.
    Drop,
}

/// One round-2 value that the party claims about the cell it shares with another party.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Claim {
    /// The value from the row or column the party holds.
    Honest,
    /// The honest value plus a random constant.
    Lie,
    /// For the party's own dealing only: the value that the other party holds for this cell,
    /// so that the pair does not disagree in round 2. For other dealers this acts as
    /// [`Claim::Honest`].
    FollowDealt,
}

/// The cell value the party broadcasts in round 3 as the dealer of a disputed triple.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum DealerAnswer {
    /// The value of the dealer's table.
    Truth,
    /// The value that Pi holds, from what the dealer sent Pi in round 1.
    SideWithPi,
    /// The value that Pj holds, from what the dealer sent Pj in round 1.
    SideWithPj,
    /// Side with whichever of Pi and Pj holds a dealing other than the true table, so the
    /// dealer defends its round-1 lie. The truth if both or neither do.
    DefendDealt,
    /// A random value.
    Random,
    /// One value fewer than the batch size.
    ShortBatch,
    /// No entry for the triple.
    Omit,
}

/// The value the party broadcasts in round 3 as Pi or Pj of a disputed triple.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum PartyAnswer {
    /// The value from the row or column the party holds.
    Honest,
    /// The unpadded value that the party claimed for this cell in round 2.
    RepeatClaim,
    /// A random value.
    Random,
    /// One value fewer than the batch size.
    ShortBatch,
    /// No entry for the triple.
    Omit,
}

/// The row the party broadcasts in round 4 as the dealer, for one party.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum DealerRow {
    /// The row of the dealer's table.
    TrueRow,
    /// The row that the unhappy party received in round 1 (zero if it rejected the message).
    DealtRow,
    /// The row of the second table.
    OtherTableRow,
    /// The row of the table that most of the voters hold columns of.
    MajorityRow,
    /// A random row of degree t.
    RandomRow,
    /// The true row plus a term of degree t + 1.
    WrongDegree,
    /// The zero row, which matches the zeros that a voter without a message counts as.
    ZeroRow,
    /// The true rows without the last secret of the batch.
    ShortBatch,
    /// The values of the true row at zero, instead of polynomials.
    WrongType,
    /// No entry for the party.
    Omit,
}

/// The value the party broadcasts in round 4 as a voter on a conflict.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Vote {
    /// The value of the party's column at the unhappy party's point.
    Honest,
    /// A random value.
    Random,
    /// The constant polynomials of the honest values, instead of values.
    WrongType,
    /// No entry for the conflict.
    Omit,
}

/// The secrets of a batch that a lie changes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum LieScope {
    /// Every secret of the batch.
    All,
    /// One secret of the batch, chosen by [`VssDecisions::index`].
    One,
}

/// The source of the choices that a [`FuzzedVss`] party makes.
///
/// The party calls the methods in protocol order, and in sorted role order within a round, so
/// a deterministic source gives a deterministic execution.
pub trait VssDecisions: Send + Sync {
    /// Returns what to send to `receiver` in round 1.
    fn deal(&self, receiver: Role) -> Deal;
    /// Returns how to take part in the broadcast of `round` (2, 3 or 4).
    fn participation(&self, round: usize) -> Participation;
    /// Returns the round-2 claim about the cell shared with `party` in the dealing of `dealer`.
    /// `column` is true for the value from the party's column, false for its row.
    fn claim(&self, dealer: Role, party: Role, column: bool) -> Claim;
    /// Returns the round-3 answer as the dealer of the triple `(self, pi, pj)`.
    fn dealer_answer(&self, pi: Role, pj: Role) -> DealerAnswer;
    /// Returns the round-3 answer in the dealing of `dealer`, against `other`.
    /// `as_pi` is true if the party is Pi of the triple, false if it is Pj.
    fn party_answer(&self, dealer: Role, other: Role, as_pi: bool) -> PartyAnswer;
    /// Returns the round-4 row for `unhappy_party` as the dealer.
    fn dealer_row(&self, unhappy_party: Role) -> DealerRow;
    /// Returns the row to add, as the dealer, to the round-4 broadcast for `party`, which is not
    /// unhappy with the dealing. `None` adds nothing, as the honest protocol does. Honest
    /// parties must not take a share from such a row.
    fn unrequested_row(&self, party: Role) -> Option<DealerRow>;
    /// Returns the round-4 vote on the conflict between `dealer` and `unhappy_party`.
    fn vote(&self, dealer: Role, unhappy_party: Role) -> Vote;
    /// Returns the number of entries to add to the round-3 broadcast for random triples that are
    /// not disputed or do not include the party. Honest parties must ignore them.
    fn extra_answers(&self) -> usize;
    /// Returns the secrets of the batch that the next lie changes.
    fn lie_scope(&self) -> LieScope;
    /// Returns an index below `len`, with `len > 0`.
    fn index(&self, len: usize) -> usize;
}

/// A VSS party that sends what its [`VssDecisions`] choose. See the module documentation.
#[derive(Clone)]
pub struct FuzzedVss<BCast: Broadcast> {
    broadcast: BCast,
    decisions: Arc<dyn VssDecisions>,
}

impl<BCast: Broadcast> FuzzedVss<BCast> {
    /// Returns a party that broadcasts with `broadcast_strategy` and asks `decisions` what to send.
    pub fn new(broadcast_strategy: &BCast, decisions: Arc<dyn VssDecisions>) -> Self {
        Self {
            broadcast: broadcast_strategy.clone(),
            decisions,
        }
    }
}

impl<BCast: Broadcast> ProtocolDescription for FuzzedVss<BCast> {
    fn protocol_desc(depth: usize) -> String {
        let indent = Self::INDENT_STRING.repeat(depth);
        format!("{}-FuzzedVss:\n{}", indent, BCast::protocol_desc(depth + 1))
    }
}

/// Which table a receiver's round-1 dealing comes from.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Table {
    True,
    Other,
    Neither,
}

/// What one receiver holds for the party's own dealing after round 1.
struct Held<Z: Ring> {
    /// The row and column pairs the receiver uses: zeros if it rejected or missed the message.
    polys: Vec<DoublePoly<Z>>,
    /// True if the receiver got the party's round-1 pads. A receiver that rejected or missed
    /// the message uses zero pads.
    got_pads: bool,
    table: Table,
}

/// The state that the dealing and the round-2 claims leave for rounds 3 and 4.
struct DealState<Z: Ring> {
    true_polys: Vec<BivariatePoly<Z>>,
    other_polys: Vec<BivariatePoly<Z>>,
    held: HashMap<Role, Held<Z>>,
}

#[async_trait]
impl<BCast: Broadcast> Vss for FuzzedVss<BCast> {
    fn num_rounds(num_parties: usize, threshold: usize) -> usize {
        SecureVss::num_rounds(num_parties, threshold)
    }

    async fn execute_many<Z: RingWithExceptionalSequence, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        secrets: &[Z],
    ) -> anyhow::Result<Vec<Vec<Z>>> {
        let num_secrets = secrets.len();
        let num_parties = session.num_parties();
        let my_role = session.my_role();
        let all_roles = session.get_all_sorted_roles().clone();

        let (state, vss) = self.fuzzed_round_1(session, secrets).await?;

        // Round 2.
        let claims = match self.decisions.participation(2) {
            Participation::Drop => return Ok(Vec::new()),
            Participation::Malformed => {
                self.broadcast_malformed::<Z, S>(session).await?;
                return Ok(Vec::new());
            }
            Participation::Send => self.round_2_claims(session, &vss, &state)?,
        };
        let verification_vector = claims.padded.clone();
        let bcast_data = self
            .broadcast
            .broadcast_from_all_w_corrupt_set_update(
                session,
                BroadcastValue::Round2VSS(verification_vector),
            )
            .await?;
        // Same bookkeeping as the honest round 2.
        let mut verification_map: HashMap<Role, Option<Vec<VerificationValues<Z>>>> = bcast_data
            .into_iter()
            .map(|(role, value)| {
                (
                    role,
                    verify_round_2_broadcast(role, value, num_parties, num_secrets),
                )
            })
            .collect();
        for (role, result) in verification_map.iter() {
            if result.is_none() {
                session.add_corrupt(*role);
            }
        }
        for corrupt_role in session.corrupt_roles().iter() {
            verification_map.insert(*corrupt_role, None);
        }
        // A session never adds its own role to its corrupt set, so the party checks for itself
        // whether the honest parties now treat it as corrupt. They then ignore it, and it stops.
        if verification_map.get(&my_role).is_none_or(Option::is_none) {
            return Ok(Vec::new());
        }

        // Round 3.
        let potentially_unhappy =
            find_potential_conflicts_for_all_roles(&verification_map, &all_roles);
        let unhappy_vec = if potentially_unhappy.is_empty() {
            vec![HashSet::new(); num_parties]
        } else {
            match self.decisions.participation(3) {
                Participation::Drop => return Ok(Vec::new()),
                Participation::Malformed => {
                    self.broadcast_malformed::<Z, S>(session).await?;
                    return Ok(Vec::new());
                }
                Participation::Send => {}
            }
            let msg = self.round_3_answers(session, &potentially_unhappy, &vss, &state, &claims)?;
            let settlements = self
                .broadcast
                .broadcast_from_all_w_corrupt_set_update(session, BroadcastValue::Round3VSS(msg))
                .await?;
            // Same bookkeeping as the honest round 3.
            let (unhappy_vec, malicious_bcast) =
                find_real_conflicts(num_secrets, &potentially_unhappy, settlements, num_parties);
            let threshold = session.threshold() as usize;
            if malicious_bcast.contains(&my_role) || unhappy_vec[&my_role].len() > threshold {
                return Ok(Vec::new());
            }
            for role in malicious_bcast {
                session.add_corrupt(role);
            }
            for (dealer_idx, unhappy_set) in unhappy_vec.iter().enumerate() {
                if unhappy_set.len() > threshold {
                    session.add_corrupt(Role::indexed_from_zero(dealer_idx));
                }
            }
            unhappy_vec
        };

        // Round 4. The output of this party is never used, so it skips the honest vote count.
        if unhappy_vec
            .iter()
            .any(|unhappy_set| !unhappy_set.is_empty())
        {
            match self.decisions.participation(4) {
                Participation::Drop => return Ok(Vec::new()),
                Participation::Malformed => {
                    self.broadcast_malformed::<Z, S>(session).await?;
                    return Ok(Vec::new());
                }
                Participation::Send => {}
            }
            let msg = self.round_4_message(session, &unhappy_vec, &vss, &state)?;
            self.broadcast
                .broadcast_from_all_w_corrupt_set_update(session, BroadcastValue::Round4VSS(msg))
                .await?;
        }
        Ok(vec![vec![Z::ZERO; num_secrets]; num_parties])
    }
}

impl<BCast: Broadcast> FuzzedVss<BCast> {
    /// Deals the party's secrets as its decisions choose, then receives the other dealings.
    async fn fuzzed_round_1<Z: RingWithExceptionalSequence, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        secrets: &[Z],
    ) -> anyhow::Result<(DealState<Z>, Round1VSSOutput<Z>)> {
        let num_secrets = secrets.len();
        let my_role = session.my_role();
        let degree = session.threshold() as usize;
        let (true_polys, honest_shares) = sample_secret_polys(session, secrets)?;
        let other_secrets = (0..num_secrets)
            .map(|_| Z::sample(session.rng()))
            .collect_vec();
        let (other_polys, other_shares) = sample_secret_polys(session, &other_secrets)?;
        let zeros = vec![DoublePoly::<Z>::default(); num_secrets];

        let mut to_send: MapRoleDoublePoly<Z> = HashMap::new();
        to_send.insert(my_role, honest_shares[&my_role].clone());
        let mut held = HashMap::new();
        for receiver in session.get_all_sorted_roles().clone() {
            if receiver == my_role {
                continue;
            }
            let honest = honest_shares[&receiver].clone();
            let (sent, kept) = match self.decisions.deal(receiver) {
                Deal::Honest => (Some(honest.clone()), Some((honest, Table::True))),
                Deal::OtherTable => {
                    let other = other_shares[&receiver].clone();
                    (Some(other.clone()), Some((other, Table::Other)))
                }
                choice @ (Deal::ShiftedRow | Deal::ShiftedColumn) => {
                    let shift_row = choice == Deal::ShiftedRow;
                    let mut shifted = honest;
                    for idx in self.lie_indices(num_secrets) {
                        let shift = Poly::from_coefs(vec![nonzero(session)]);
                        let target = if shift_row {
                            &mut shifted[idx].share_in_x
                        } else {
                            &mut shifted[idx].share_in_y
                        };
                        *target = &*target + &shift;
                    }
                    (Some(shifted.clone()), Some((shifted, Table::Neither)))
                }
                choice @ (Deal::PartialRow | Deal::PartialColumn) => {
                    let mut candidates = session
                        .get_all_sorted_roles()
                        .iter()
                        .copied()
                        .filter(|role| *role != my_role && *role != receiver)
                        .collect_vec();
                    let mut vanishing = Poly::from_coefs(vec![Z::ONE]);
                    for _ in 0..degree.min(candidates.len()) {
                        let role = candidates.remove(self.decisions.index(candidates.len()));
                        let point = Z::embed_role_to_exceptional_sequence(&role)?;
                        vanishing = &vanishing * &Poly::from_coefs(vec![-point, Z::ONE]);
                    }
                    let mut shifted = honest;
                    for idx in self.lie_indices(num_secrets) {
                        let shift = &vanishing * &nonzero::<Z, S>(session);
                        let target = if choice == Deal::PartialRow {
                            &mut shifted[idx].share_in_x
                        } else {
                            &mut shifted[idx].share_in_y
                        };
                        *target = &*target + &shift;
                    }
                    (Some(shifted.clone()), Some((shifted, Table::Neither)))
                }
                Deal::WrongDegree => {
                    let mut coefs = vec![Z::ZERO; degree + 2];
                    coefs[degree + 1] = Z::ONE;
                    let extra = Poly::from_coefs(coefs);
                    let mut wrong = honest;
                    wrong[0].share_in_x = &wrong[0].share_in_x + &extra;
                    (Some(wrong), None)
                }
                Deal::WrongLength => {
                    let mut wrong = honest;
                    wrong.push(DoublePoly::default());
                    (Some(wrong), None)
                }
                Deal::Silent => (None, None),
            };
            if let Some(sent) = sent {
                to_send.insert(receiver, sent);
            }
            let held_by_receiver = match kept {
                Some((polys, table)) => Held {
                    polys,
                    got_pads: true,
                    table,
                },
                None => Held {
                    polys: zeros.clone(),
                    got_pads: false,
                    table: Table::Neither,
                },
            };
            held.insert(receiver, held_by_receiver);
        }

        let vss = round_1(session, num_secrets, true_polys.clone(), to_send).await?;
        Ok((
            DealState {
                true_polys,
                other_polys,
                held,
            },
            vss,
        ))
    }

    /// Computes the round-2 values with the party's claims applied.
    fn round_2_claims<Z: RingWithExceptionalSequence, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        vss: &Round1VSSOutput<Z>,
        state: &DealState<Z>,
    ) -> anyhow::Result<Claims<Z>> {
        let num_secrets = vss.my_poly.len();
        let my_role = session.my_role();
        let my_point = Z::embed_role_to_exceptional_sequence(&my_role)?;
        let all_roles = session.get_all_sorted_roles().clone();
        let mut padded = Vec::with_capacity(all_roles.len());
        let mut unpadded = HashMap::new();
        for dealer in all_roles.iter() {
            let mut per_party = Vec::with_capacity(all_roles.len());
            for party in all_roles.iter() {
                let mut values =
                    generate_verification_value(num_secrets, &my_role, party, dealer, vss)?;
                if party != &my_role {
                    let my_pads = &vss.sent_challenges[party][dealer];
                    let their_pads = &vss.received_vss[party].challenges_list[dealer];
                    let mut rows = values
                        .iter()
                        .zip_eq(my_pads)
                        .map(|((a, _), pad)| *a - *pad)
                        .collect_vec();
                    let mut columns = values
                        .iter()
                        .zip_eq(their_pads)
                        .map(|((_, b), pad)| *b - *pad)
                        .collect_vec();
                    let mut row_pads = my_pads.clone();
                    let held = (dealer == &my_role).then(|| &state.held[party]);
                    for column in [false, true] {
                        let target = if column { &mut columns } else { &mut rows };
                        match (self.decisions.claim(*dealer, *party, column), held) {
                            (Claim::Lie, _) => {
                                for idx in self.lie_indices(num_secrets) {
                                    target[idx] += nonzero(session);
                                }
                            }
                            (Claim::FollowDealt, Some(held)) => {
                                // The party's row value of the cell is the other party's column
                                // value, and the other way around.
                                for (idx, value) in target.iter_mut().enumerate() {
                                    let poly = if column {
                                        &held.polys[idx].share_in_x
                                    } else {
                                        &held.polys[idx].share_in_y
                                    };
                                    *value = poly.eval(&my_point);
                                }
                                if !column && !held.got_pads {
                                    row_pads = vec![Z::ZERO; num_secrets];
                                }
                            }
                            (Claim::Honest, _) | (Claim::FollowDealt, None) => {}
                        }
                    }
                    values = rows
                        .iter()
                        .zip_eq(&row_pads)
                        .zip_eq(columns.iter().zip_eq(their_pads))
                        .map(|((a, a_pad), (b, b_pad))| (*a + *a_pad, *b + *b_pad))
                        .collect_vec();
                    unpadded.insert((*dealer, *party), (rows, columns));
                }
                per_party.push(values);
            }
            padded.push(per_party);
        }
        Ok(Claims { padded, unpadded })
    }

    /// Builds the round-3 message with the party's answers applied.
    fn round_3_answers<Z: RingWithExceptionalSequence, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        potentially_unhappy: &HashSet<(Role, Role, Role)>,
        vss: &Round1VSSOutput<Z>,
        state: &DealState<Z>,
        claims: &Claims<Z>,
    ) -> anyhow::Result<BTreeMap<(Role, Role, Role), Vec<Z>>> {
        let my_role = session.my_role();
        let num_secrets = vss.my_poly.len();
        let mut msg = answer_to_potential_conflicts(potentially_unhappy, &my_role, vss)?;
        let keys = msg.keys().copied().collect_vec();
        for key @ (dealer, pi, pj) in keys {
            let point_i = Z::embed_role_to_exceptional_sequence(&pi)?;
            let point_j = Z::embed_role_to_exceptional_sequence(&pj)?;
            // [answer_to_potential_conflicts] answers as the dealer when the party is both the
            // dealer and Pi or Pj, so the same order applies here.
            let replacement: Option<Vec<Z>> = if dealer == my_role {
                match self.decisions.dealer_answer(pi, pj) {
                    DealerAnswer::Truth => continue,
                    DealerAnswer::SideWithPi => Some(
                        (0..num_secrets)
                            .map(|idx| self.row_of(state, vss, pi, idx).eval(&point_j))
                            .collect(),
                    ),
                    DealerAnswer::SideWithPj => Some(
                        (0..num_secrets)
                            .map(|idx| self.column_of(state, vss, pj, idx).eval(&point_i))
                            .collect(),
                    ),
                    DealerAnswer::DefendDealt => {
                        let deviant = |role: Role| {
                            state
                                .held
                                .get(&role)
                                .is_some_and(|h| h.table != Table::True)
                        };
                        match (deviant(pi), deviant(pj)) {
                            (true, false) => Some(
                                (0..num_secrets)
                                    .map(|idx| self.row_of(state, vss, pi, idx).eval(&point_j))
                                    .collect(),
                            ),
                            (false, true) => Some(
                                (0..num_secrets)
                                    .map(|idx| self.column_of(state, vss, pj, idx).eval(&point_i))
                                    .collect(),
                            ),
                            _ => continue,
                        }
                    }
                    DealerAnswer::Random => Some(self.random_values(session, &msg[&key])),
                    DealerAnswer::ShortBatch => Some(short(&msg[&key])),
                    DealerAnswer::Omit => None,
                }
            } else {
                let as_pi = pi == my_role;
                let other = if as_pi { pj } else { pi };
                match self.decisions.party_answer(dealer, other, as_pi) {
                    PartyAnswer::Honest => continue,
                    PartyAnswer::RepeatClaim => {
                        let (rows, columns) = &claims.unpadded[&(dealer, other)];
                        Some(if as_pi { rows.clone() } else { columns.clone() })
                    }
                    PartyAnswer::Random => Some(self.random_values(session, &msg[&key])),
                    PartyAnswer::ShortBatch => Some(short(&msg[&key])),
                    PartyAnswer::Omit => None,
                }
            };
            match replacement {
                Some(values) => {
                    msg.insert(key, values);
                }
                None => {
                    msg.remove(&key);
                }
            }
        }
        let roles = session.get_all_sorted_roles().clone();
        for _ in 0..self.decisions.extra_answers() {
            let key = (
                roles[self.decisions.index(roles.len())],
                roles[self.decisions.index(roles.len())],
                roles[self.decisions.index(roles.len())],
            );
            if !potentially_unhappy.contains(&key) || ![key.0, key.1, key.2].contains(&my_role) {
                let values = self.random_values(session, &vec![Z::ZERO; num_secrets]);
                msg.insert(key, values);
            }
        }
        Ok(msg)
    }

    /// Builds the round-4 message with the party's rows and votes applied.
    fn round_4_message<Z: RingWithExceptionalSequence, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        unhappy_vec: &[HashSet<Role>],
        vss: &Round1VSSOutput<Z>,
        state: &DealState<Z>,
    ) -> anyhow::Result<BTreeMap<(Role, Role), ValueOrPoly<Z>>> {
        let my_role = session.my_role();
        let mut msg = BTreeMap::new();
        for (dealer_idx, unhappy_set) in unhappy_vec.iter().enumerate() {
            let dealer = Role::indexed_from_zero(dealer_idx);
            // The honest round 4 skips the same dealings.
            if unhappy_set.contains(&my_role) || session.corrupt_roles().contains(&dealer) {
                continue;
            }
            for pi in unhappy_set.iter().copied().sorted() {
                let point_i = Z::embed_role_to_exceptional_sequence(&pi)?;
                let entry = if dealer == my_role {
                    let choice = self.decisions.dealer_row(pi);
                    self.dealer_entry(session, choice, pi, unhappy_set, vss, state)?
                } else {
                    let honest = vss.received_vss[&dealer]
                        .double_poly_list
                        .iter()
                        .map(|poly| poly.share_in_y.eval(&point_i))
                        .collect_vec();
                    match self.decisions.vote(dealer, pi) {
                        Vote::Honest => Some(ValueOrPoly::Value(honest)),
                        Vote::Random => {
                            Some(ValueOrPoly::Value(self.random_values(session, &honest)))
                        }
                        Vote::WrongType => Some(ValueOrPoly::Poly(
                            honest.iter().map(|v| Poly::from_coefs(vec![*v])).collect(),
                        )),
                        Vote::Omit => None,
                    }
                };
                if let Some(entry) = entry {
                    msg.insert((dealer, pi), entry);
                }
            }
        }
        // Rows for parties that are not unhappy with the party's own dealing. The honest round 4
        // sends none; whatever reads the broadcast must ignore them.
        let my_unhappy = &unhappy_vec[&my_role];
        for party in session.get_all_sorted_roles().clone() {
            if party == my_role || my_unhappy.contains(&party) {
                continue;
            }
            if let Some(choice) = self.decisions.unrequested_row(party)
                && let Some(entry) =
                    self.dealer_entry(session, choice, party, my_unhappy, vss, state)?
            {
                msg.insert((my_role, party), entry);
            }
        }
        Ok(msg)
    }

    /// Returns the round-4 entry of the party's own dealing for `party`, as `choice` selects.
    fn dealer_entry<Z: RingWithExceptionalSequence, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        choice: DealerRow,
        party: Role,
        unhappy_set: &HashSet<Role>,
        vss: &Round1VSSOutput<Z>,
        state: &DealState<Z>,
    ) -> anyhow::Result<Option<ValueOrPoly<Z>>> {
        let my_role = session.my_role();
        let degree = session.threshold() as usize;
        let num_secrets = vss.my_poly.len();
        let point = Z::embed_role_to_exceptional_sequence(&party)?;
        let true_rows = state
            .true_polys
            .iter()
            .map(|poly| poly.partial_y_eval(point))
            .collect_vec();
        let rows = match choice {
            DealerRow::TrueRow => true_rows,
            DealerRow::DealtRow => (0..num_secrets)
                .map(|idx| self.row_of(state, vss, party, idx))
                .collect(),
            DealerRow::OtherTableRow => state
                .other_polys
                .iter()
                .map(|poly| poly.partial_y_eval(point))
                .collect(),
            DealerRow::MajorityRow => {
                let voters = session
                    .get_all_sorted_roles()
                    .iter()
                    .filter(|role| {
                        !unhappy_set.contains(role) && **role != party && **role != my_role
                    })
                    .map(|role| state.held[role].table)
                    .collect_vec();
                let other = voters.iter().filter(|t| **t == Table::Other).count();
                let true_count = voters.iter().filter(|t| **t == Table::True).count();
                let polys = if other > true_count {
                    &state.other_polys
                } else {
                    &state.true_polys
                };
                polys
                    .iter()
                    .map(|poly| poly.partial_y_eval(point))
                    .collect()
            }
            DealerRow::RandomRow => (0..num_secrets)
                .map(|_| {
                    let constant = Z::sample(session.rng());
                    Poly::sample_random_with_fixed_constant(session.rng(), constant, degree)
                })
                .collect(),
            DealerRow::WrongDegree => {
                let mut coefs = vec![Z::ZERO; degree + 2];
                coefs[degree + 1] = Z::ONE;
                let extra = Poly::from_coefs(coefs);
                true_rows.iter().map(|row| row + &extra).collect()
            }
            DealerRow::ZeroRow => vec![Poly::from_coefs(vec![Z::ZERO]); num_secrets],
            DealerRow::ShortBatch => short(&true_rows),
            DealerRow::WrongType => {
                return Ok(Some(ValueOrPoly::Value(
                    true_rows.iter().map(|row| row.eval(&Z::ZERO)).collect(),
                )));
            }
            DealerRow::Omit => return Ok(None),
        };
        Ok(Some(ValueOrPoly::Poly(rows)))
    }

    /// Broadcasts a value that no VSS round accepts.
    async fn broadcast_malformed<Z: Ring, S: BaseSessionHandles>(
        &self,
        session: &mut S,
    ) -> anyhow::Result<()> {
        self.broadcast
            .broadcast_from_all_w_corrupt_set_update(session, BroadcastValue::<Z>::Bot)
            .await?;
        Ok(())
    }

    /// Returns the row that `role` holds for the party's own dealing.
    fn row_of<Z: Ring>(
        &self,
        state: &DealState<Z>,
        vss: &Round1VSSOutput<Z>,
        role: Role,
        idx: usize,
    ) -> Poly<Z> {
        match state.held.get(&role) {
            Some(held) => held.polys[idx].share_in_x.clone(),
            None => vss.received_vss[&role].double_poly_list[idx]
                .share_in_x
                .clone(),
        }
    }

    /// Returns the column that `role` holds for the party's own dealing.
    fn column_of<Z: Ring>(
        &self,
        state: &DealState<Z>,
        vss: &Round1VSSOutput<Z>,
        role: Role,
        idx: usize,
    ) -> Poly<Z> {
        match state.held.get(&role) {
            Some(held) => held.polys[idx].share_in_y.clone(),
            None => vss.received_vss[&role].double_poly_list[idx]
                .share_in_y
                .clone(),
        }
    }

    /// Returns `honest` with a random constant added to the secrets that the lie scope selects.
    fn random_values<Z: Ring, S: BaseSessionHandles>(
        &self,
        session: &mut S,
        honest: &[Z],
    ) -> Vec<Z> {
        let mut values = honest.to_vec();
        for idx in self.lie_indices(values.len()) {
            values[idx] += nonzero(session);
        }
        values
    }

    /// Returns the batch indices that the next lie changes.
    fn lie_indices(&self, num_secrets: usize) -> Vec<usize> {
        match self.decisions.lie_scope() {
            LieScope::All => (0..num_secrets).collect(),
            LieScope::One => vec![self.decisions.index(num_secrets)],
        }
    }
}

/// The round-2 values of the party, padded as broadcast and unpadded per `(dealer, party)`
/// as `(row values, column values)`.
struct Claims<Z: Ring> {
    padded: Vec<VerificationValues<Z>>,
    unpadded: HashMap<(Role, Role), (Vec<Z>, Vec<Z>)>,
}

/// Returns `values` without its last element.
fn short<T: Clone>(values: &[T]) -> Vec<T> {
    values[..values.len().saturating_sub(1)].to_vec()
}

/// Returns a random ring element that is not zero.
fn nonzero<Z: Ring, S: BaseSessionHandles>(session: &mut S) -> Z {
    let value = Z::sample(session.rng());
    if value == Z::ZERO { Z::ONE } else { value }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::communication::broadcast::SyncReliableBroadcast;
    use crate::runtime::sessions::base_session::GenericBaseSessionHandles;
    use crate::runtime::sessions::large_session::LargeSession;
    use crate::tests::helper::tests::{
        TestingParameters, execute_protocol_large_w_disputes_and_malicious,
    };
    use algebra::galois_rings::degree_4::ResiduePolyF4Z64;
    use algebra::sharing::shamir::{RevealOp, ShamirSharings};
    use algebra::sharing::share::Share;
    use algebra::structure_traits::{Sample, Zero};
    use threshold_types::network::NetworkMode;

    type Z = ResiduePolyF4Z64;

    /// Decisions that deal with `deal` and claim with `claim`, and are honest everywhere else.
    /// The receiver of `special_deal` gets its deal instead of `deal`, the dealer answers
    /// round 3 with `dealer_answer`, and every party that is not unhappy gets
    /// `unrequested_row` in round 4.
    struct Fixed {
        deal: Deal,
        claim: Claim,
        special_deal: Option<(Role, Deal)>,
        dealer_answer: DealerAnswer,
        unrequested_row: Option<DealerRow>,
    }

    impl Fixed {
        fn new(deal: Deal, claim: Claim) -> Self {
            Self {
                deal,
                claim,
                special_deal: None,
                dealer_answer: DealerAnswer::Truth,
                unrequested_row: None,
            }
        }
    }

    impl VssDecisions for Fixed {
        fn deal(&self, receiver: Role) -> Deal {
            match self.special_deal {
                Some((role, deal)) if role == receiver => deal,
                _ => self.deal,
            }
        }
        fn participation(&self, _round: usize) -> Participation {
            Participation::Send
        }
        fn claim(&self, _dealer: Role, _party: Role, _column: bool) -> Claim {
            self.claim
        }
        fn dealer_answer(&self, _pi: Role, _pj: Role) -> DealerAnswer {
            self.dealer_answer
        }
        fn party_answer(&self, _dealer: Role, _other: Role, _as_pi: bool) -> PartyAnswer {
            PartyAnswer::Honest
        }
        fn dealer_row(&self, _unhappy_party: Role) -> DealerRow {
            DealerRow::TrueRow
        }
        fn vote(&self, _dealer: Role, _unhappy_party: Role) -> Vote {
            Vote::Honest
        }
        fn unrequested_row(&self, _party: Role) -> Option<DealerRow> {
            self.unrequested_row
        }
        fn extra_answers(&self) -> usize {
            0
        }
        fn lie_scope(&self) -> LieScope {
            LieScope::All
        }
        fn index(&self, _len: usize) -> usize {
            0
        }
    }

    /// The outcome of one VSS with party 1 as the [`FuzzedVss`] party.
    struct Outcome {
        /// For each dealer and secret, the value of the honest shares, if they are consistent.
        opened: Vec<Vec<Option<Z>>>,
        liar_secrets: Vec<Z>,
        liar_marked_corrupt: bool,
    }

    async fn run(decisions: Fixed, num_secrets: usize) -> Outcome {
        let params = TestingParameters::init(4, 1, &[0], &[], &[], false, None);
        let liar = Role::indexed_from_zero(0);
        let fuzzed = FuzzedVss::new(&SyncReliableBroadcast::default(), Arc::new(decisions));
        let mut task_honest = |mut session: LargeSession| async move {
            let secrets = (0..num_secrets)
                .map(|_| Z::sample(session.rng()))
                .collect_vec();
            let out = SecureVss::default()
                .execute_many(&mut session, &secrets)
                .await
                .unwrap();
            (out, session.corrupt_roles().clone())
        };
        let mut task_malicious = |mut session: LargeSession, fuzzed: FuzzedVss<_>| async move {
            let secrets = (0..num_secrets)
                .map(|_| Z::sample(session.rng()))
                .collect_vec();
            let _ = fuzzed.execute_many(&mut session, &secrets).await;
            secrets
        };
        let (honest, malicious) = execute_protocol_large_w_disputes_and_malicious::<
            _,
            _,
            _,
            _,
            _,
            Z,
            { Z::EXTENSION_DEGREE },
        >(
            &params,
            &[],
            &params.malicious_roles,
            fuzzed,
            NetworkMode::Sync,
            None,
            &mut task_honest,
            &mut task_malicious,
        )
        .await;
        let opened = (0..params.num_parties)
            .map(|dealer| {
                (0..num_secrets)
                    .map(|k| {
                        let shares = honest
                            .iter()
                            .map(|(role, (out, _))| Share::new(*role, out[dealer][k]))
                            .collect_vec();
                        ShamirSharings::create(shares).reconstruct(1).ok()
                    })
                    .collect()
            })
            .collect();
        Outcome {
            opened,
            liar_secrets: malicious.into_values().next().unwrap().unwrap(),
            liar_marked_corrupt: honest.values().all(|(_, corrupt)| corrupt.contains(&liar)),
        }
    }

    #[tokio::test]
    async fn honest_decisions_share_the_input_secrets() {
        let outcome = run(Fixed::new(Deal::Honest, Claim::Honest), 2).await;
        assert!(!outcome.liar_marked_corrupt);
        let liar_opened: Vec<Option<Z>> = outcome.liar_secrets.iter().map(|s| Some(*s)).collect();
        assert_eq!(outcome.opened[0], liar_opened);
        assert!(outcome.opened.iter().flatten().all(Option::is_some));
    }

    #[tokio::test]
    async fn malformed_dealing_to_everyone_throws_the_dealer_out() {
        let outcome = run(Fixed::new(Deal::WrongDegree, Claim::Honest), 1).await;
        assert!(outcome.liar_marked_corrupt);
        assert_eq!(outcome.opened[0], vec![Some(Z::ZERO)]);
    }

    #[tokio::test]
    async fn second_table_to_everyone_is_accepted_with_another_secret() {
        let outcome = run(Fixed::new(Deal::OtherTable, Claim::FollowDealt), 1).await;
        assert!(!outcome.liar_marked_corrupt);
        let opened = outcome.opened[0][0].expect("honest shares are consistent");
        assert_ne!(opened, outcome.liar_secrets[0]);
    }

    /// The dealer makes party 2 unhappy, so round 4 runs, and repairs party 2 honestly. It also
    /// broadcasts a random row for every other party, which no party asked for.
    fn unrequested_random_rows() -> Fixed {
        Fixed {
            special_deal: Some((Role::indexed_from_one(2), Deal::ShiftedRow)),
            unrequested_row: Some(DealerRow::RandomRow),
            ..Fixed::new(Deal::Honest, Claim::Honest)
        }
    }

    #[tokio::test]
    #[ignore = "fails: round 4 of VSS takes a share from any row the dealer broadcasts for the party, unhappy or not"]
    async fn unrequested_round_4_rows_do_not_change_honest_shares() {
        let outcome = run(unrequested_random_rows(), 1).await;
        assert!(!outcome.liar_marked_corrupt);
        assert!(
            outcome.opened[0][0].is_some(),
            "the honest shares of the dealing do not lie on one polynomial of degree t"
        );
    }

    /// The dealer (party 1) gives party 2 a row that still matches the column of party 3, but
    /// not the column of party 4. It claims in round 2 what it dealt, so only the pair (2, 4)
    /// disagrees. It sides with party 2 in round 3, so only party 4 is unhappy, and it repairs
    /// party 4 with its true row in round 4, which both voters accept.
    fn row_matching_t_columns() -> Fixed {
        Fixed {
            special_deal: Some((Role::indexed_from_one(2), Deal::PartialRow)),
            dealer_answer: DealerAnswer::SideWithPi,
            ..Fixed::new(Deal::Honest, Claim::FollowDealt)
        }
    }

    #[tokio::test]
    #[ignore = "fails: no party compares its own row and column, so a row that matches t columns survives"]
    async fn row_matching_t_columns_keeps_honest_shares_consistent() {
        let outcome = run(row_matching_t_columns(), 1).await;
        assert!(!outcome.liar_marked_corrupt);
        assert!(
            outcome.opened[0][0].is_some(),
            "the honest shares of the dealing do not lie on one polynomial of degree t"
        );
    }
}
