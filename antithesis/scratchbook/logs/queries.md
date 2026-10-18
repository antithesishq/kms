# Live-check queries

Failure query (live-debugging.md), used for every stream:

```
FAILED='filter(ev => (a => a && a.hit && ((a.assert_type == "always" && a.condition === false) || (a.assert_type == "reachability" && !a.must_hit)))(ev.antithesis_assert))'
```
