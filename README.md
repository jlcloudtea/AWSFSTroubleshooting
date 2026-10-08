# AWSFSTroubleshooting

AWS Cloud Fundamentals troubleshooting exercise in `us-east-1`. Students repair the public route, HTTP security group, Auto Scaling capacity, and daily scheduled actions.

## Test branch

In a fresh Learner Lab terminal:

```bash
git clone -b feature/troubleshooting-verification-page https://github.com/jlcloudtea/AWSFSTroubleshooting TRscript
cd TRscript
bash run.sh
```

Choose **1** to create the environment. The startup commands and the original menu numbers 1–3 remain the same. Once creation completes, troubleshoot the environment in the AWS console.

The EC2 instance serves an assessment page at its public HTTP address. You can see the page once the route and security group have been repaired. To check the full solution, run `bash run.sh` again and choose **4) Verify (trial)**. The direct command still works:

```bash
python3 verify.py
```

When web access works, option 4 uploads a snapshot to the first reachable instance and prints its home page URL. Refresh the page (or wait up to 15 seconds) to see the latest result and earlier reports in newest-first order. The home page shows four assessment items: Problem 1-1 Route table, Problem 1-2 Security group, Problem 2-1 Autoscaling options, and Problem 2-2 Schedule Policy. Passing all four displays `Good Job.`; unfinished items show only `NOT SUCCESS`.

The verifier also prints a snapshot link as a fallback. If HTTP is still inaccessible, rely on the terminal results; the instance page cannot load until web access is restored. History is limited to the latest 50 reports on one EC2 instance and disappears if that instance is replaced. Different Auto Scaling instances have separate histories. This is practice feedback rather than a secure grading record.

Create two recurring daily actions in the same time zone, **without end dates**: 09:00 sets Min 2 / Desired 3 / Max 4; 11:00 sets Min 1 / Desired 2 / Max 3. The verifier accepts an explicit time zone or AWS's default UTC. It checks configuration and the current capacities; a report obtained before 09:00 cannot prove tomorrow's action actually executed.

Choose **2** in `bash run.sh` to delete the stack. Template changes do not update an already running EC2 instance automatically. Delete and recreate the test stack to try the lighter web server bootstrap and new home page.

UserData installs Apache, PHP and CloudFormation helper scripts. A PHP endpoint stores reports on the instance. MySQL, MariaDB, the external ZIP download, and archive tools are not needed. The stack gets a per-stack upload token from `run.sh`; keep the same `TRscript` directory to let option 4 publish reports. No new IAM role is required for this upload. The EC2 endpoint is plain HTTP, so the upload token and result history are appropriate only for this disposable practice lab.
