//! The VSS properties, checked on the outcome of one session.
//!
//! All invariants assume at most t liars, which the main loop guarantees, and no honest party
//! that timed out waiting for another honest party. A timeout makes the slow honest party look
//! like a silent liar, so the session would have more than t faulty parties.

use std::collections::{BTreeSet, HashSet};

use algebra::poly::Poly;
use algebra::sharing::shamir::ShamirSharings;
use algebra::sharing::share::Share;
use algebra::structure_traits::ErrorCorrect;
use itertools::Itertools;
use serde_json::{Value, json};
use threshold_execution::large_execution::vss_observer::VssEvent;
use threshold_types::role::Role;

use crate::session::Observed;
use crate::{always, sometimes};

fn ids<'a>(roles: impl IntoIterator<Item = &'a Role>) -> Vec<usize> {
    roles.into_iter().map(|r| r.one_based()).sorted().collect()
}

/// The round-3 view of one party, with sets in sorted order so views compare as values.
#[derive(PartialEq, Eq, Debug, Clone)]
struct Round3View {
    potentially_unhappy: Vec<(usize, usize, usize)>,
    unhappy: Vec<Vec<usize>>,
    corrupt: Vec<usize>,
}

/// One round-4 vote of one party, sorted for comparison.
#[derive(PartialEq, Eq, Debug, Clone, PartialOrd, Ord)]
struct VoteView {
    dealer: usize,
    unhappy_party: usize,
    voters: Vec<usize>,
    yes_voters: Vec<usize>,
    dealer_thrown_out: bool,
}

/// The events of one party, grouped by round.
struct PartyView {
    round2: Vec<Vec<usize>>,
    round3: Vec<Round3View>,
    votes: Vec<VoteView>,
    round4: Vec<(Vec<usize>, Vec<usize>)>,
}

fn party_view(events: &[VssEvent]) -> PartyView {
    let mut view = PartyView {
        round2: Vec::new(),
        round3: Vec::new(),
        votes: Vec::new(),
        round4: Vec::new(),
    };
    for event in events {
        match event {
            VssEvent::Round2 { corrupt } => view.round2.push(ids(corrupt)),
            VssEvent::Round3 {
                potentially_unhappy,
                unhappy,
                corrupt,
            } => view.round3.push(Round3View {
                potentially_unhappy: potentially_unhappy
                    .iter()
                    .map(|(d, i, j)| (d.one_based(), i.one_based(), j.one_based()))
                    .sorted()
                    .collect(),
                unhappy: unhappy.iter().map(ids).collect(),
                corrupt: ids(corrupt),
            }),
            VssEvent::Round4Vote {
                dealer,
                unhappy_party,
                voters,
                yes_voters,
                dealer_thrown_out,
            } => view.votes.push(VoteView {
                dealer: dealer.one_based(),
                unhappy_party: unhappy_party.one_based(),
                voters: ids(voters),
                yes_voters: ids(yes_voters),
                dealer_thrown_out: *dealer_thrown_out,
            }),
            VssEvent::Round4 {
                corrupt,
                repaired_from,
            } => view.round4.push((ids(corrupt), ids(repaired_from))),
        }
    }
    view.votes.sort();
    view
}

/// Returns the polynomial of degree at most `degree` through all `shares`, if there is one.
/// The decoder result is checked against every share, so a decoder bug cannot hide an
/// inconsistent sharing.
fn interpolate<Z: ErrorCorrect>(shares: &[(Role, Z)], degree: usize) -> Option<Poly<Z>> {
    let sharing = ShamirSharings::create(
        shares
            .iter()
            .map(|(role, value)| Share::new(*role, *value))
            .collect(),
    );
    let poly = Z::error_correct(&sharing, degree, 0).ok()?;
    let fits = poly.deg() <= degree
        && shares.iter().all(|(role, value)| {
            Z::embed_role_to_exceptional_sequence(role)
                .map(|point| poly.eval(&point) == *value)
                .unwrap_or(false)
        });
    fits.then_some(poly)
}

/// Checks every property on the outcome of one session.
pub fn check<Z: ErrorCorrect>(observed: &Observed<Z>, num_parties: usize, batch_size: usize) {
    let t = observed.threshold;
    let honest = &observed.honest;
    let liars = &observed.liars;
    let base = json!({ "honest": ids(honest), "liars": ids(liars), "t": t });
    let with = |extra: Value| {
        let mut details = base.clone();
        if let (Some(d), Value::Object(e)) = (details.as_object_mut(), extra) {
            d.extend(e);
        }
        details
    };

    let completed = observed.finished
        && honest.iter().all(|role| {
            matches!(observed.outputs.get(role), Some(Ok(out))
                if out.len() == num_parties && out.iter().all(|shares| shares.len() == batch_size))
        });
    let errors: Vec<(usize, String)> = observed
        .outputs
        .iter()
        .filter_map(|(role, result)| result.as_ref().err().map(|e| (role.one_based(), e.clone())))
        .collect();
    always!(
        completed,
        "VSS: every honest party completes the VSS with one share per dealer and secret",
        with(json!({ "finished": observed.finished, "errors": errors }))
    );
    always!(
        observed.honest_timeouts.is_empty(),
        "VSS: no honest party times out waiting for another honest party",
        with(json!({
            "timeouts": observed.honest_timeouts.iter().map(|(s, r)| (s.one_based(), r.one_based())).collect_vec()
        }))
    );
    if !completed || !observed.honest_timeouts.is_empty() {
        return;
    }

    // Corrupt sets at the end of the VSS.
    let corrupt_sets: Vec<Vec<usize>> = honest.iter().map(|r| ids(&observed.corrupt[r])).collect();
    always!(
        corrupt_sets.iter().all_equal(),
        "VSS: honest parties agree on the corrupt set",
        with(json!({ "corrupt_sets": corrupt_sets }))
    );
    let honest_marked: BTreeSet<usize> = observed
        .corrupt
        .values()
        .flat_map(|set| {
            set.iter()
                .filter(|r| honest.contains(r))
                .map(|r| r.one_based())
        })
        .collect();
    always!(
        honest_marked.is_empty(),
        "VSS: no honest party is marked corrupt",
        with(json!({ "honest_marked_corrupt": honest_marked, "corrupt_sets": corrupt_sets }))
    );

    // The sets of the dispute resolution, as each honest party reports them.
    let views: Vec<(Role, PartyView)> = honest
        .iter()
        .map(|r| {
            (
                *r,
                party_view(observed.events.get(r).map(Vec::as_slice).unwrap_or(&[])),
            )
        })
        .collect();
    let reported = views
        .iter()
        .all(|(_, v)| v.round2.len() == 1 && v.round3.len() == 1 && v.round4.len() == 1);
    always!(
        reported,
        "VSS: every honest party reports rounds 2, 3 and 4 to the observer",
        with(json!({
            "counts": views.iter().map(|(r, v)| (r.one_based(), v.round2.len(), v.round3.len(), v.round4.len())).collect_vec()
        }))
    );
    if !reported {
        return;
    }
    let round3: Vec<&Round3View> = views.iter().map(|(_, v)| &v.round3[0]).collect();
    always!(
        views.iter().map(|(_, v)| &v.round2[0]).all_equal() && round3.iter().all_equal(),
        "VSS: honest parties compute the same disputed triples and unhappy sets",
        with(json!({
            "round2_corrupt": views.iter().map(|(r, v)| (r.one_based(), v.round2[0].clone())).collect_vec(),
            "round3": format!("{round3:?}"),
        }))
    );
    always!(
        views
            .iter()
            .map(|(_, v)| (&v.votes, &v.round4[0].0))
            .all_equal(),
        "VSS: honest parties count the same round-4 votes",
        with(json!({
            "votes": views.iter().map(|(r, v)| (r.one_based(), format!("{:?}", v.votes))).collect_vec()
        }))
    );

    let liar_ids: HashSet<usize> = ids(liars).into_iter().collect();
    let honest_ids: HashSet<usize> = ids(honest).into_iter().collect();
    for (role, view) in views.iter() {
        let r3 = &view.round3[0];
        // The comment at the end of round 4 in vss.rs: a party takes its share from round 4
        // exactly when it is unhappy with the dealer, because then the dealer broadcast its row.
        let unrequested: Vec<usize> = view.round4[0]
            .1
            .iter()
            .copied()
            .filter(|dealer| !r3.unhappy[dealer - 1].contains(&role.one_based()))
            .collect();
        always!(
            unrequested.is_empty(),
            "VSS: an honest party takes a share from round 4 only for a dealer it is unhappy with",
            with(json!({
                "observer": role.one_based(),
                "dealers_without_unhappiness": unrequested,
                "repaired_from": view.round4[0].1,
            }))
        );
        let liar_free: Vec<_> = r3
            .potentially_unhappy
            .iter()
            .filter(|(d, i, j)| ![d, i, j].iter().any(|p| liar_ids.contains(p)))
            .collect();
        always!(
            liar_free.is_empty(),
            "VSS: every disputed triple involves a liar",
            with(json!({ "observer": role.one_based(), "liar_free_triples": liar_free }))
        );
        let honest_unhappy_with_honest: Vec<(usize, Vec<usize>)> = r3
            .unhappy
            .iter()
            .enumerate()
            .filter(|(d, _)| honest_ids.contains(&(d + 1)))
            .map(|(d, set)| {
                (
                    d + 1,
                    set.iter()
                        .copied()
                        .filter(|p| honest_ids.contains(p))
                        .collect_vec(),
                )
            })
            .filter(|(_, set)| !set.is_empty())
            .collect();
        always!(
            honest_unhappy_with_honest.is_empty(),
            "VSS: an honest party is unhappy only with a lying dealer",
            with(
                json!({ "observer": role.one_based(), "honest_dealer_unhappy_sets": honest_unhappy_with_honest })
            )
        );
        for vote in view.votes.iter() {
            let corrupt_yes: Vec<usize> = vote
                .yes_voters
                .iter()
                .copied()
                .filter(|v| r3.corrupt.contains(v))
                .collect();
            // A voter without a message counts as zeros, so a corrupt voter supports a dealer
            // whose row is zero at its point. With at most t liars this gives no extra power,
            // so it is a reach claim, not an invariant.
            sometimes!(
                !corrupt_yes.is_empty(),
                "VSS: a party marked corrupt before round 4 counts as a yes vote",
                with(
                    json!({ "observer": role.one_based(), "vote": format!("{vote:?}"), "corrupt_yes_voters": corrupt_yes })
                )
            );
            if honest_ids.contains(&vote.dealer) {
                let against: Vec<usize> = vote
                    .voters
                    .iter()
                    .copied()
                    .filter(|v| honest_ids.contains(v) && !vote.yes_voters.contains(v))
                    .collect();
                always!(
                    against.is_empty() && !vote.dealer_thrown_out,
                    "VSS: honest voters vote for an honest dealer",
                    with(
                        json!({ "observer": role.one_based(), "vote": format!("{vote:?}"), "against": against })
                    )
                );
            }
        }
    }

    // The shares: one polynomial per dealing and secret, through the honest outputs. A dealing
    // that an unrequested round-4 row changed already fails the round-4 property above, so the
    // shape check leaves it out and can still show other causes.
    let final_corrupt: HashSet<usize> = corrupt_sets[0].iter().copied().collect();
    let unrequested_dealers: BTreeSet<usize> = views
        .iter()
        .flat_map(|(role, view)| {
            let unhappy = &view.round3[0].unhappy;
            view.round4[0]
                .1
                .iter()
                .copied()
                .filter(|dealer| !unhappy[dealer - 1].contains(&role.one_based()))
                .collect_vec()
        })
        .collect();
    let mut bad_dealings = Vec::new();
    let mut wrong_secrets = Vec::new();
    let mut liar_value_changed = false;
    for dealer_idx in 0..num_parties {
        let dealer = Role::indexed_from_zero(dealer_idx);
        if unrequested_dealers.contains(&dealer.one_based()) {
            continue;
        }
        for k in 0..batch_size {
            let shares: Vec<(Role, Z)> = honest
                .iter()
                .map(|r| {
                    let out = observed.outputs[r].as_ref().expect("completed implies Ok");
                    (*r, out[dealer_idx][k])
                })
                .collect();
            match interpolate(&shares, t) {
                None => bad_dealings.push((dealer.one_based(), k)),
                Some(poly) => {
                    let value = poly.eval(&Z::ZERO);
                    let input = observed.secrets[&dealer][k];
                    if honest.contains(&dealer) && value != input {
                        wrong_secrets.push((dealer.one_based(), k));
                    }
                    if liars.contains(&dealer)
                        && !final_corrupt.contains(&dealer.one_based())
                        && value != input
                    {
                        liar_value_changed = true;
                    }
                }
            }
        }
    }
    always!(
        bad_dealings.is_empty(),
        "VSS: each dealing gives the honest parties shares on one polynomial of degree at most t",
        with(json!({
            "inconsistent_dealer_secret_pairs": bad_dealings,
            "left_out_for_unrequested_rows": unrequested_dealers,
        }))
    );
    always!(
        wrong_secrets.is_empty(),
        "VSS: the honest parties' shares of an honest dealer open to its secret",
        with(json!({ "wrong_dealer_secret_pairs": wrong_secrets }))
    );

    // Reach claims: the session shapes the workload must reach for the invariants to matter.
    let r3 = round3[0];
    let votes = &views[0].1.votes;
    sometimes!(
        liars.len() == t,
        "VSS: a session runs with t liars",
        base.clone()
    );
    sometimes!(
        !r3.potentially_unhappy.is_empty(),
        "VSS: a session reaches round 3",
        base.clone()
    );
    sometimes!(
        r3.unhappy.iter().any(|set| !set.is_empty()),
        "VSS: a session reaches round 4",
        base.clone()
    );
    sometimes!(
        r3.unhappy
            .iter()
            .enumerate()
            .any(|(d, set)| liar_ids.contains(&(d + 1)) && set.len() > t),
        "VSS: a lying dealer is thrown out in round 3",
        base.clone()
    );
    sometimes!(
        votes
            .iter()
            .any(|v| liar_ids.contains(&v.dealer) && v.dealer_thrown_out),
        "VSS: a lying dealer is thrown out in round 4",
        base.clone()
    );
    sometimes!(
        r3.unhappy.iter().enumerate().any(|(d, set)| {
            liar_ids.contains(&(d + 1))
                && !final_corrupt.contains(&(d + 1))
                && set.iter().any(|p| honest_ids.contains(p))
        }),
        "VSS: a lying dealer that made an honest party unhappy is not thrown out",
        base.clone()
    );
    sometimes!(
        views
            .iter()
            .any(|(_, v)| v.round4[0].1.iter().any(|d| liar_ids.contains(d))),
        "VSS: an honest party takes its share of a lying dealer from round 4",
        base.clone()
    );
    sometimes!(
        observed.liar_deviations > 0 && liar_ids.iter().any(|l| !final_corrupt.contains(l)),
        "VSS: a liar that deviated finishes without being marked corrupt",
        base.clone()
    );
    sometimes!(
        liar_value_changed,
        "VSS: a lying dealer's accepted sharing opens to a value other than its input",
        base
    );
}
