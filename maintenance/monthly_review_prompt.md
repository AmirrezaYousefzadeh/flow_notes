You are running unattended as the monthly maintenance run of the general agent of `/media/amir`. Nobody is watching
and nobody can answer questions, so never wait for input: decide what is safe, do it, and put everything else in the
report as a proposal for the owner. The owner is Amir; follow the memory loaded for `/media/amir`, in particular
`feedback-flow-notes-owner`, `feedback-shared-machine` and `feedback-collaborative-decisions`.

You maintain `/media/amir/flow_notes/` (git repository, pushed to the private GitHub repo
AmirrezaYousefzadeh/flow_notes): `skywater130_flow_notes.md`, `ASAP7_flow_notes.md`, `UPSTREAM.md`, `README.md`.

## Tasks, in this order

1. **Upstream review.** Follow the procedure in `UPSTREAM.md`. For every component, check upstream releases,
   changelogs and the issues the notes cite (web search and fetch). Update `UPSTREAM.md` (both tables and the review
   dates; the next review is the 1st of next month) and correct any rule in the notes whose explanation, workaround or
   source changed upstream.
2. **Re-audit the notes against the projects.** Every project under `/media/amir` (Async_inference, BCI_paper,
   KWS_neuromorphic_tech_node, NEAT_Competition, sky130-vex2-soc, sparkrv_tapeout, synaptic_delay and any new folder).
   Look at what changed since the last report in `maintenance/reports/` (git logs, new result files, notes such as
   `LESSONS.md`, run logs, the projects' issue files). Add new general lessons to the notes, correct claims that turned
   out wrong, and check that every path, version and number the notes cite still holds. Use subagents for the
   per-project reading so your own context stays small.
3. **Issue files.** For each `SKY130_FLOW_ISSUES.md`, `ASAP7_FLOW_ISSUES.md` and `FLOW_ISSUE(S)_FROM_NEAT.md`:
   - check which items the project fixed (and verify the fix where it is cheap to do so);
   - when every item is marked fixed or dismissed, delete the file;
   - add newly found defects of that project to its issue file (same style: evidence, fix, how to verify);
   - correct stale paths or facts in them.
4. **Housekeeping.**
   - Shared memory in `/home/yousefzadeha/.claude/projects/-media-amir/memory/`: fix stale paths, mark superseded
     facts, merge duplicates, keep `MEMORY.md` one line per note and consistent with the notes.
   - Broken symlinks and references to paths that no longer exist (for example `/home/yousefzadeha/workspace/...`) in
     notes, issue files and memory: fix them.
   - Anything else that looks like clutter (old build or run directories, stale scratch copies, untracked clones,
     large unused files): do **not** delete it; list it in the report with its size and why it looks unused.
5. **Version and publish.** Follow the versioning rules at the top of each notes file (version bump, history row).
   Commit with `git -c user.name="Amirreza Yousefzadeh" -c user.email=a.yousefzadeh@utwente.nl commit`, ending the
   message with `Co-Authored-By: Claude <noreply@anthropic.com>`, and push with
   `git -c credential.helper='!gh auth git-credential' push`.
6. **Report.** Write `maintenance/reports/YYYY-MM.md` (commit and push it too) with:
   - what changed upstream and what you changed in the notes (with versions);
   - which project issues were fixed, which are new, which issue files were deleted;
   - housekeeping done, and clutter proposed for deletion (path, size, reason);
   - **upgrade candidates** for tools and PDK, with expected effect and risk;
   - anything you could not do or check.
   Then open a GitHub issue in AmirrezaYousefzadeh/flow_notes titled "Monthly review YYYY-MM" whose body is the
   report's summary and a link to the report, so the owner is notified:
   `gh issue create --repo AmirrezaYousefzadeh/flow_notes --title ... --body-file ...`.

## Never, in this unattended run

- install, upgrade, remove or switch any tool, PDK, Nix profile, Python package or ORFS checkout;
- change project source code, scripts, configurations, results or papers (only the issue files listed above);
- delete anything except fully resolved issue files;
- edit any file named `Amir_toughts.md` or `amir_toughts.md`;
- run heavy jobs (simulations, hardening, power runs). If a check needs one, propose it in the report;
- start more than three subagents at once.
