# Monthly maintenance

On the 1st of every month at 04:00, cron runs `run_monthly_review.sh`, which starts Claude Code headless from
`/media/amir` with `monthly_review_prompt.md`. The run:
1. processes the inbox and keeps it empty;
2. reviews upstream (tools, PDKs, macros) and updates `UPSTREAM.md` and the notes;
3. reads the projects (read-only) for unreported flow lessons and adds them to the notes in general terms;
4. does housekeeping (`flow_notes`, memory), and lists clutter for the owner instead of deleting it;
5. announces in `ANNOUNCEMENTS.md` what users must act on;
6. commits and pushes, writes `reports/YYYY-MM.md`, and opens a GitHub issue "Monthly review YYYY-MM" so the owner
   gets a notification.

It never installs or upgrades tools or PDKs and never writes into project folders: upgrades are proposed in the report and
installed only after the owner approves them.

- Cron entry (`crontab -l`): `0 4 1 * * /media/amir/flow_notes/maintenance/run_monthly_review.sh`
- Logs: `maintenance/logs/` (not committed). A failed run also opens a GitHub issue.
- Run it by hand: `/media/amir/flow_notes/maintenance/run_monthly_review.sh`
- Stop it: remove the line with `crontab -e`.
