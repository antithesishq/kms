# Log-only evidence gathered after `runs exec` refused (run completed). snouty = antithesis/build/bin/snouty.
RUN=5a41ff4512a62b259c30d0cf245647d8-64-4
# every bind failure in the run (2 events, under the 999 limit, so complete)
snouty --json runs search $RUN 'contains({output_text: "Could not bind"})' -n 999 > logs-search-could-not-bind.ndjson
# every panic in the run (704 events, under the limit, so complete; all but 2 are kms-core-client)
snouty --json runs search $RUN 'contains({output_text: "panicked at"})' -n 999 > logs-search-panicked-at.ndjson
# the sibling branch that panicked at 1123.24, from vtime 1040
snouty --json runs logs $RUN 3318742107607495774 1123.25 --begin-vtime 1040 > ../../logs/iterate-3-bindpanic-branch-3318742107607495774.ndjson
