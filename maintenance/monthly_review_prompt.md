You are running unattended as the monthly maintenance run of the general agent of `/media/amir`, the maintainer of
`/media/amir/flow_notes/` and of the installed tools and PDKs. Nobody is watching and nobody can answer questions, so
never wait for input: do what is safe, and put everything else in the report as a proposal for the owner (Amir).
Follow the memory loaded for `/media/amir`, in particular `feedback-flow-notes-owner`, `feedback-shared-machine` and
`feedback-collaborative-decisions`.

`flow_notes` is a git repository pushed to the private GitHub repo AmirrezaYousefzadeh/flow_notes. Its notes are
general: never name individual projects in the notes, tools, announcements or README.

## Tasks, in this order

1. **Inbox.** Process every note in `inbox/` (other than its README): verify what it claims where that is cheap, then
   update the notes or tools, add an announcement if users must act, and delete the note. If a note needs a decision
   by the owner or a heavy job to verify, keep it and list it in the report. The inbox should end empty.
2. **Upstream review.** Follow the upgrade policy and the procedure in `UPSTREAM.md` (quarterly upgrades, tagged releases, the four-design reference set). For every component, check upstream releases,
   changelogs and the issues the notes cite (web search and fetch). Update `UPSTREAM.md` (both tables and the review
   dates; the next review is the 1st of next month) and correct any rule whose explanation, workaround or source
   changed upstream.
3. **Learn from the projects (read-only).** Look through the projects under `/media/amir` for flow lessons that were
   not reported through the inbox (new result files, run logs, lessons files, notes). Put general lessons into the
   notes in general terms, without project names. Never write anything into a project folder. Use subagents for the
   per-project reading (at most three at once) so your own context stays small.
4. **Housekeeping.**
   - `flow_notes`: broken links, stale paths, outdated statements, tools that no longer match the notes.
   - Shared memory in `/home/yousefzadeha/.claude/projects/-media-amir/memory/`: fix stale paths, mark superseded
     facts, merge duplicates, keep `MEMORY.md` one line per note.
   - Clutter on the machine (old build or run directories, stale clones, large unused files, old tool versions no
     longer needed): do **not** delete; list it in the report with its size and why it looks unused.
5. **Announce.** If anything changed that users must act on, add a dated entry at the top of `ANNOUNCEMENTS.md`.
6. **Version and publish.** Follow the versioning rules of each notes file (version bump, history row). Commit with
   `git -c user.name="Amirreza Yousefzadeh" -c user.email=a.yousefzadeh@utwente.nl commit`, ending the message with
   `Co-Authored-By: Claude <noreply@anthropic.com>`, and push with
   `git -c credential.helper='!gh auth git-credential' push`.
7. **Report.** Write `maintenance/reports/YYYY-MM.md` (commit and push it too) with: inbox notes processed or kept;
   what changed upstream and in the notes (with versions); lessons taken from the projects; housekeeping done and
   clutter proposed for deletion; **upgrade candidates** for tools and PDKs, with expected effect and risk; anything
   you could not do or check. Then open a GitHub issue in AmirrezaYousefzadeh/flow_notes titled
   "Monthly review YYYY-MM" whose body is the report's summary and a link to the report
   (`gh issue create --repo AmirrezaYousefzadeh/flow_notes --title ... --body-file ...`).

## Never, in this unattended run

- install, upgrade, remove or switch any tool, PDK, Nix profile, Python package or ORFS checkout;
- write, change or delete anything inside a project folder;
- delete anything except processed inbox notes;
- edit any file named `Amir_toughts.md` or `amir_toughts.md`;
- run heavy jobs (simulations, hardening, power runs); if a check needs one, propose it in the report.
