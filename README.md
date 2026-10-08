# AWSFSTroubleshooting

AWS Cloud Fundamentals troubleshooting exercise in `us-east-1`. Students repair the public route, HTTP security group, Auto Scaling capacity, and daily scheduled actions.

## Test branch

In a fresh Learner Lab terminal:

```bash
git clone -b feature/troubleshooting-verification-page https://github.com/jlcloudtea/AWSFSTroubleshooting TRscript
cd TRscript
bash run.sh
```

Choose **1** to create the environment. The menu and startup commands have not changed. Once creation completes, troubleshoot the environment in the AWS console.

The EC2 instance serves a static assessment page at its public HTTP address. You can see the page once the route and security group have been repaired. To check the full solution and generate a report link, run from `TRscript`:

```bash
python3 verify.py
```

Open the complete URL printed by the verifier. It uses the instance's home page and displays all five checks: route, HTTP security group, daily schedule, current capacity, and live HTTP response. The link carries a snapshot of the terminal result in its fragment. Re-run the command for an updated result. This is practice feedback, not a secure grading record.

Create two recurring daily actions in the same time zone, **without end dates**: 09:00 sets Min 2 / Desired 3 / Max 4; 11:00 sets Min 1 / Desired 2 / Max 3. The verifier accepts an explicit time zone or AWS's default UTC. It checks configuration and the current capacities; a report obtained before 09:00 cannot prove tomorrow's action actually executed.

Choose **2** in `bash run.sh` to delete the stack. Template changes do not update an already running EC2 instance automatically. Delete and recreate the test stack to try the lighter web server bootstrap and new home page.

The site is static HTML. UserData installs Apache and CloudFormation helper scripts; PHP, MySQL, MariaDB, the external ZIP download, and archive tools are no longer needed for this assessment.
