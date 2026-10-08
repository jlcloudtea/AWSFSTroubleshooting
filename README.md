# AWSFSTroubleshooting

This troubleshooting cloudformation yml file is created for cloud foundamental subject.
The student need to tourlbeshoot EC2, Network and Autoscaling issues in zone us-east-1.
You need to run it in your AWS CLI enviroment in academy website. 

Target: Fix the web access to the Public IP address and autoscaling issues.

Download the script and run in bash envoriment.

git clone https://github.com/jlcloudtea/AWSFSTroubleshooting TRscript

cd TRscript

bash run.sh

Then follow the prompt message to create, delete the AWS cloudfomration enviroment. 


## Verification page (test branch)

The existing create/delete menu is unchanged. To test this branch in a fresh Learner Lab:

```bash
git clone -b feature/troubleshooting-verification-page https://github.com/jlcloudtea/AWSFSTroubleshooting TRscript
cd TRscript
bash run.sh
```

Choose **1** to create the environment. After completing the troubleshooting in the AWS console, run:

```bash
python3 verify.py
```

The script reads the current stack and prints five checks: the public route, HTTP security group, daily scheduled actions, current Auto Scaling capacity, and a live HTTP response. It prints a report URL for an in-service instance with a public IP. Open that complete URL in a browser to see the results on the lab web server. If the public route or HTTP security group is still wrong, the report page may not load yet; use the terminal results to continue troubleshooting, then rerun the script.

The assessment's daily 09:00 and 11:00 actions should use the same time zone. The script accepts an explicitly selected time zone or AWS's default UTC; it checks the current group capacity against the active window. A daily 11:00 return action is required. The script only reads AWS settings and never repairs them. The link contains the report data in its fragment, which is processed locally by the browser. This is student feedback, not a secure grading record.

The original `bash run.sh` menu still offers **2** to delete the environment.
