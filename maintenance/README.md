# Monthly maintenance

On the 1st of every month at 04:00, cron runs `run_monthly_review.sh`, which starts Claude Code headless from
`/media/amir` with `monthly_review_prompt.md`. The run:
1. reviews upstream (tools, PDKs, macros) and updates `UPSTREAM.md` and the notes;
2. re-audits the notes against every project;
3. updates the projects' issue files, and deletes those whose items are all fixed;
4. does housekeeping (stale paths, memory), and lists clutter for the owner instead of deleting it;
5. commits and pushes, writes `reports/YYYY-MM.md`, and opens a GitHub issue "Monthly review YYYY-MM" so the owner
   gets a notification.

It never installs or upgrades tools or PDKs and never changes project code: upgrades are proposed in the report and
installed only after the owner approves them.

- Cron entry (`crontab -l`): `0 4 1 * * /media/amir/flow_notes/maintenance/run_monthly_review.sh`
- Logs: `maintenance/logs/` (not committed). A failed run also opens a GitHub issue.
- Run it by hand: `/media/amir/flow_notes/maintenance/run_monthly_review.sh`
- Stop it: remove the line with `crontab -e`.
