# AWSFSTroubleshooting

AWS Cloud Fundamentals troubleshooting exercise in `us-east-1`. Students repair the public route, HTTP security group, Auto Scaling capacity, and daily scheduled actions.

## Start the lab

In a fresh Learner Lab terminal:

```bash
git clone https://github.com/jlcloudtea/AWSFSTroubleshooting TRscript
cd TRscript
bash run.sh
```

Choose **1** to create the environment. Once creation completes, troubleshoot the environment in the AWS console.

The EC2 instance serves a static assessment page at its public HTTP address. You can see the page once the route and security group have been repaired. To check the full solution and generate a report link, run `bash run.sh` again and choose **4) Verify (trial)**. The direct command still works:

```bash
python3 verify.py
```

Open the complete URL printed by the verifier. The instance's home page shows four assessment items: Problem 1-1 Route table, Problem 1-2 Security group, Problem 2-1 Autoscaling options, and Problem 2-2 Schedule Policy. A live HTTP request is included in the web access check. Passing all four displays `Good Job.`; unfinished items show `NOT SUCCESS` without exposing the wrong configuration.

The link carries a snapshot of the terminal result in its fragment. Opening it once stores that result in the same browser, so refreshing the home page keeps the latest result seen there. Re-run option 4 and open its new link to update it. The terminal cannot change the public page for other browsers. This is feedback on current work, not a grading record. If HTTP is still inaccessible, use the terminal result; the instance page cannot load until web access is restored.

Create two recurring daily actions in the same time zone, **without end dates**: 09:00 sets Min 2 / Desired 3 / Max 4; 11:00 sets Min 1 / Desired 2 / Max 3. The verifier accepts an explicit time zone or AWS's default UTC. It checks configuration and the current capacities; a report obtained before 09:00 cannot prove tomorrow's action actually executed.

Choose **2** in `bash run.sh` to delete the stack. Template changes do not update an already running EC2 instance automatically. Delete and recreate the stack to use a revised template or home page.

The site is static HTML. UserData installs Apache and CloudFormation helper scripts; PHP, MySQL, MariaDB, the external ZIP download, and archive tools are no longer needed for this assessment.
