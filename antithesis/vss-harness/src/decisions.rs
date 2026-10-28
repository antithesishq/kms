//! The random [`VssDecisions`] of one liar, with a swarm profile drawn per session.
//!
//! A profile gives each decision point a deviation probability from a menu that includes the
//! extremes, and drops some deviations entirely. So one session concentrates on a few kinds of
//! lies, and across sessions every combination comes up.

use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::json;
use threshold_execution::malicious_execution::large_execution::fuzzed_vss::{
    Claim, Deal, DealerAnswer, DealerRow, LieScope, Participation, PartyAnswer, Vote, VssDecisions,
};
use threshold_types::role::Role;

use crate::sdk::{chance, index, pick};
use crate::sometimes;

/// Deviation probabilities. The menu covers "never", "rarely", "often" and "almost always".
const LIE_RATES: [f64; 5] = [0.0, 0.05, 0.3, 0.9, 1.0];
/// Leaving the protocol ends a liar's influence, so it stays rare.
const LEAVE_RATES: [f64; 3] = [0.0, 0.02, 0.2];

/// Returns the deviations a decision point allows in one session. With probability 1/3 it
/// keeps one deviation, so the liar repeats one coherent lie, such as dealing every receiver
/// the second table. Otherwise it drops each deviation with probability 1/4, never all.
fn swarm<T: Copy>(options: &[T]) -> Vec<T> {
    if chance(1.0 / 3.0) {
        return vec![pick(options)];
    }
    let kept: Vec<T> = options.iter().copied().filter(|_| !chance(0.25)).collect();
    if kept.is_empty() {
        options.to_vec()
    } else {
        kept
    }
}

/// The deviation probability and the allowed deviations of one decision point.
struct Point<T> {
    rate: f64,
    deviations: Vec<T>,
}

impl<T: Copy + std::fmt::Debug> Point<T> {
    fn draw(rates: &[f64], deviations: &[T]) -> Self {
        Self {
            rate: pick(rates),
            deviations: swarm(deviations),
        }
    }

    /// Returns a deviation with the point's probability, else `honest`.
    fn choose(&self, honest: T, count: &AtomicU64) -> T {
        if chance(self.rate) {
            count.fetch_add(1, Ordering::Relaxed);
            pick(&self.deviations)
        } else {
            honest
        }
    }

    fn describe(&self) -> serde_json::Value {
        json!({ "rate": self.rate, "deviations": format!("{:?}", self.deviations) })
    }
}

/// Returns a decision point that never deviates.
fn never<T>(deviations: Vec<T>) -> Point<T> {
    Point {
        rate: 0.0,
        deviations,
    }
}

/// The decisions of one liar in one session.
pub struct LiarDecisions {
    role: Role,
    /// In the coherent profile, the only receiver that gets a deviating dealing.
    target: Option<Role>,
    deal: Point<Deal>,
    leave: Point<Participation>,
    claim_own: Point<Claim>,
    claim_other: Point<Claim>,
    dealer_answer: Point<DealerAnswer>,
    party_answer: Point<PartyAnswer>,
    dealer_row: Point<DealerRow>,
    unrequested_row: Point<Option<DealerRow>>,
    vote: Point<Vote>,
    extra_answers: Point<usize>,
    one_secret_rate: f64,
    deviations: AtomicU64,
}

impl LiarDecisions {
    /// Draws a profile for the liar `role` in a session of `num_parties` parties.
    ///
    /// One profile in three is coherent: the liar deals one target receiver a deviating
    /// dealing and then hides it. It claims in round 2 what it dealt, defends the deviating
    /// party in round 3 and is honest everywhere else. Independent random choices almost never
    /// line up like this, and some attacks need all of them.
    pub fn draw(role: Role, num_parties: usize) -> Self {
        let free = Self::draw_free(role);
        if !chance(1.0 / 3.0) {
            return free;
        }
        let others: Vec<Role> = (1..=num_parties)
            .map(Role::indexed_from_one)
            .filter(|r| *r != role)
            .collect();
        Self {
            target: Some(pick(&others)),
            // Dealings that the pairwise checks can miss for some receivers. A malformed or
            // missing message gets the dealer thrown out or ignored anyway.
            deal: Point {
                rate: 1.0,
                deviations: swarm(&[
                    Deal::OtherTable,
                    Deal::ShiftedRow,
                    Deal::ShiftedColumn,
                    Deal::PartialRow,
                    Deal::PartialColumn,
                ]),
            },
            leave: never(vec![Participation::Drop]),
            claim_own: Point {
                rate: 1.0,
                deviations: vec![Claim::FollowDealt],
            },
            claim_other: never(vec![Claim::Lie]),
            dealer_answer: Point {
                rate: 1.0,
                deviations: vec![DealerAnswer::DefendDealt],
            },
            party_answer: never(vec![PartyAnswer::Random]),
            dealer_row: never(vec![DealerRow::RandomRow]),
            unrequested_row: never(vec![None]),
            vote: never(vec![Vote::Random]),
            extra_answers: never(vec![0]),
            ..free
        }
    }

    /// Draws a profile in which every decision point deviates independently.
    fn draw_free(role: Role) -> Self {
        Self {
            role,
            target: None,
            deal: Point::draw(
                &LIE_RATES,
                &[
                    Deal::OtherTable,
                    Deal::ShiftedRow,
                    Deal::ShiftedColumn,
                    Deal::PartialRow,
                    Deal::PartialColumn,
                    Deal::WrongDegree,
                    Deal::WrongLength,
                    Deal::Silent,
                ],
            ),
            leave: Point::draw(
                &LEAVE_RATES,
                &[Participation::Drop, Participation::Malformed],
            ),
            claim_own: Point::draw(&LIE_RATES, &[Claim::Lie, Claim::FollowDealt]),
            claim_other: Point::draw(&LIE_RATES, &[Claim::Lie]),
            dealer_answer: Point::draw(
                &LIE_RATES,
                &[
                    DealerAnswer::SideWithPi,
                    DealerAnswer::SideWithPj,
                    DealerAnswer::DefendDealt,
                    DealerAnswer::Random,
                    DealerAnswer::ShortBatch,
                    DealerAnswer::Omit,
                ],
            ),
            party_answer: Point::draw(
                &LIE_RATES,
                &[
                    PartyAnswer::RepeatClaim,
                    PartyAnswer::Random,
                    PartyAnswer::ShortBatch,
                    PartyAnswer::Omit,
                ],
            ),
            dealer_row: Point::draw(
                &LIE_RATES,
                &[
                    DealerRow::DealtRow,
                    DealerRow::OtherTableRow,
                    DealerRow::MajorityRow,
                    DealerRow::RandomRow,
                    DealerRow::WrongDegree,
                    DealerRow::ZeroRow,
                    DealerRow::ShortBatch,
                    DealerRow::WrongType,
                    DealerRow::Omit,
                ],
            ),
            unrequested_row: Point::draw(
                &LIE_RATES,
                &[
                    Some(DealerRow::TrueRow),
                    Some(DealerRow::OtherTableRow),
                    Some(DealerRow::RandomRow),
                    Some(DealerRow::WrongDegree),
                    Some(DealerRow::ZeroRow),
                    Some(DealerRow::ShortBatch),
                    Some(DealerRow::WrongType),
                ],
            ),
            vote: Point::draw(&LIE_RATES, &[Vote::Random, Vote::WrongType, Vote::Omit]),
            extra_answers: Point::draw(&LEAVE_RATES, &[1, 3]),
            one_secret_rate: pick(&[0.0, 0.5, 1.0]),
            deviations: AtomicU64::new(0),
        }
    }

    /// Returns the number of deviations the liar chose so far.
    pub fn deviations(&self) -> u64 {
        self.deviations.load(Ordering::Relaxed)
    }

    /// Returns the profile, for the session log.
    pub fn describe(&self) -> serde_json::Value {
        json!({
            "role": self.role.one_based(),
            "coherent_target": self.target.map(|r| r.one_based()),
            "deal": self.deal.describe(),
            "leave": self.leave.describe(),
            "claim_own": self.claim_own.describe(),
            "claim_other": self.claim_other.describe(),
            "dealer_answer": self.dealer_answer.describe(),
            "party_answer": self.party_answer.describe(),
            "dealer_row": self.dealer_row.describe(),
            "unrequested_row": self.unrequested_row.describe(),
            "vote": self.vote.describe(),
            "extra_answers": self.extra_answers.describe(),
            "one_secret_rate": self.one_secret_rate,
        })
    }
}

impl VssDecisions for LiarDecisions {
    fn deal(&self, receiver: Role) -> Deal {
        let choice = match self.target {
            Some(target) if target != receiver => Deal::Honest,
            _ => self.deal.choose(Deal::Honest, &self.deviations),
        };
        let details = json!({ "liar": self.role.one_based(), "receiver": receiver.one_based() });
        sometimes!(
            choice == Deal::OtherTable,
            "Liar deals a receiver the row and column of a second table",
            details.clone()
        );
        sometimes!(
            choice == Deal::ShiftedRow,
            "Liar deals a receiver a shifted row",
            details.clone()
        );
        sometimes!(
            choice == Deal::ShiftedColumn,
            "Liar deals a receiver a shifted column",
            details.clone()
        );
        sometimes!(
            matches!(choice, Deal::PartialRow | Deal::PartialColumn),
            "Liar deals a receiver a row or column that matches up to t other receivers",
            details.clone()
        );
        sometimes!(
            matches!(choice, Deal::WrongDegree | Deal::WrongLength),
            "Liar deals a receiver a malformed message",
            details.clone()
        );
        sometimes!(
            choice == Deal::Silent,
            "Liar sends nothing to a receiver in round 1",
            details
        );
        choice
    }

    fn participation(&self, round: usize) -> Participation {
        let choice = self.leave.choose(Participation::Send, &self.deviations);
        let details = json!({ "liar": self.role.one_based(), "round": round });
        sometimes!(
            choice == Participation::Drop,
            "Liar stops executing VSS before a broadcast",
            details.clone()
        );
        sometimes!(
            choice == Participation::Malformed,
            "Liar broadcasts a malformed value",
            details
        );
        choice
    }

    fn claim(&self, dealer: Role, party: Role, column: bool) -> Claim {
        let own = dealer == self.role;
        let point = if own {
            &self.claim_own
        } else {
            &self.claim_other
        };
        let choice = point.choose(Claim::Honest, &self.deviations);
        let details = json!({
            "liar": self.role.one_based(),
            "dealer": dealer.one_based(),
            "party": party.one_based(),
            "column": column,
        });
        sometimes!(
            choice == Claim::Lie && !own,
            "Liar lies in a round-2 claim about another dealer's table",
            details.clone()
        );
        sometimes!(
            choice == Claim::Lie && own,
            "Liar lies in a round-2 claim about its own table",
            details.clone()
        );
        sometimes!(
            choice == Claim::FollowDealt,
            "Liar claims in round 2 what it dealt the other party",
            details
        );
        choice
    }

    fn dealer_answer(&self, pi: Role, pj: Role) -> DealerAnswer {
        let choice = self
            .dealer_answer
            .choose(DealerAnswer::Truth, &self.deviations);
        let details =
            json!({ "liar": self.role.one_based(), "pi": pi.one_based(), "pj": pj.one_based() });
        sometimes!(
            choice == DealerAnswer::SideWithPi,
            "Liar dealer sides with Pi in round 3",
            details.clone()
        );
        sometimes!(
            choice == DealerAnswer::SideWithPj,
            "Liar dealer sides with Pj in round 3",
            details.clone()
        );
        sometimes!(
            choice == DealerAnswer::DefendDealt,
            "Liar dealer defends the party it dealt a deviating dealing in round 3",
            details.clone()
        );
        sometimes!(
            choice == DealerAnswer::Random,
            "Liar dealer answers a random value in round 3",
            details.clone()
        );
        sometimes!(
            choice == DealerAnswer::ShortBatch,
            "Liar dealer answers a short batch in round 3",
            details.clone()
        );
        sometimes!(
            choice == DealerAnswer::Omit,
            "Liar dealer omits an answer in round 3",
            details
        );
        choice
    }

    fn party_answer(&self, dealer: Role, other: Role, as_pi: bool) -> PartyAnswer {
        let choice = self
            .party_answer
            .choose(PartyAnswer::Honest, &self.deviations);
        let details = json!({
            "liar": self.role.one_based(),
            "dealer": dealer.one_based(),
            "other": other.one_based(),
            "as_pi": as_pi,
        });
        sometimes!(
            choice == PartyAnswer::RepeatClaim,
            "Liar repeats its round-2 claim in round 3",
            details.clone()
        );
        sometimes!(
            choice == PartyAnswer::Random,
            "Liar answers a random value in round 3 as Pi or Pj",
            details.clone()
        );
        sometimes!(
            choice == PartyAnswer::ShortBatch,
            "Liar answers a short batch in round 3 as Pi or Pj",
            details.clone()
        );
        sometimes!(
            choice == PartyAnswer::Omit,
            "Liar omits an answer in round 3 as Pi or Pj",
            details
        );
        choice
    }

    fn dealer_row(&self, unhappy_party: Role) -> DealerRow {
        let choice = self.dealer_row.choose(DealerRow::TrueRow, &self.deviations);
        let details =
            json!({ "liar": self.role.one_based(), "unhappy_party": unhappy_party.one_based() });
        sometimes!(
            choice == DealerRow::DealtRow,
            "Liar dealer rebroadcasts the row the unhappy party holds",
            details.clone()
        );
        sometimes!(
            choice == DealerRow::OtherTableRow,
            "Liar dealer broadcasts a row of its second table",
            details.clone()
        );
        sometimes!(
            choice == DealerRow::MajorityRow,
            "Liar dealer broadcasts the row of the voters' majority table",
            details.clone()
        );
        sometimes!(
            choice == DealerRow::RandomRow,
            "Liar dealer broadcasts a random row",
            details.clone()
        );
        sometimes!(
            choice == DealerRow::WrongDegree,
            "Liar dealer broadcasts a row of the wrong degree",
            details.clone()
        );
        sometimes!(
            choice == DealerRow::ZeroRow,
            "Liar dealer broadcasts the zero row",
            details.clone()
        );
        sometimes!(
            matches!(choice, DealerRow::ShortBatch | DealerRow::WrongType),
            "Liar dealer broadcasts a short batch or values instead of rows",
            details.clone()
        );
        sometimes!(
            choice == DealerRow::Omit,
            "Liar dealer omits a row in round 4",
            details
        );
        choice
    }

    fn unrequested_row(&self, party: Role) -> Option<DealerRow> {
        let choice = self.unrequested_row.choose(None, &self.deviations);
        let details = json!({ "liar": self.role.one_based(), "party": party.one_based() });
        sometimes!(
            choice.is_some(),
            "Liar dealer adds a round-4 row for a party that is not unhappy",
            details.clone()
        );
        sometimes!(
            matches!(choice, Some(DealerRow::ShortBatch | DealerRow::WrongType)),
            "Liar dealer adds a malformed round-4 entry for a party that is not unhappy",
            details
        );
        choice
    }

    fn extra_answers(&self) -> usize {
        let count = self.extra_answers.choose(0, &self.deviations);
        sometimes!(
            count > 0,
            "Liar adds round-3 answers for triples that are not its disputes",
            json!({ "liar": self.role.one_based(), "count": count })
        );
        count
    }

    fn vote(&self, dealer: Role, unhappy_party: Role) -> Vote {
        let choice = self.vote.choose(Vote::Honest, &self.deviations);
        let details = json!({
            "liar": self.role.one_based(),
            "dealer": dealer.one_based(),
            "unhappy_party": unhappy_party.one_based(),
        });
        sometimes!(
            choice == Vote::Random,
            "Liar votes a random value in round 4",
            details.clone()
        );
        sometimes!(
            choice == Vote::WrongType,
            "Liar votes with polynomials instead of values in round 4",
            details.clone()
        );
        sometimes!(
            choice == Vote::Omit,
            "Liar omits its vote in round 4",
            details
        );
        choice
    }

    fn lie_scope(&self) -> LieScope {
        if chance(self.one_secret_rate) {
            LieScope::One
        } else {
            LieScope::All
        }
    }

    fn index(&self, len: usize) -> usize {
        index(len)
    }
}
