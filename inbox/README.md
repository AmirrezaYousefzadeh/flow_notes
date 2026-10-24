# Inbox

Project agents and engineers do not edit the flow notes. To report a finding, add one file here per finding:

`YYYY-MM-DD_<project>_<short-topic>.md`, containing:
- which notes file and section it concerns (or "new");
- the symptom, how you detected it, the fix, and the measured size of the effect;
- where the evidence is (paths, log lines, commits);
- whether it is general or specific to your project.

Do not commit or push; just leave the file. The owner asks the maintainer (the general agent of `/media/amir`) to
process the inbox. The maintainer updates the notes, deletes the processed notes and, if needed, answers through the
project's file in `/media/amir/flow_notes/projects/`.
