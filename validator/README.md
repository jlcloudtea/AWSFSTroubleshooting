# Self-validation dashboard — Version 1 (draft)

This adds a **Pass/Fail-only**, read-only check page to the existing Apache/PHP troubleshooting lab. It does **not** repair any intentionally broken resources.

## Student workflow

1. Run `bash run.sh` (option 1) in AWS Academy Learner Lab, **us-east-1**.
2. Troubleshoot using AWS Console as before.
3. Open `http://<current-EC2-public-IP>/validation/` after the HTTP routing/security-group issues are fixed.
4. Click **Refresh checks** to run live checks. Submit the troubleshooting table and screenshots separately.

## Five checks

| Check | True when |
|---|---|
| HTTP | Intended instance SG allows TCP 80 from 0.0.0.0/0 and local Apache responds 200 on / |
| Routing | Both public subnets use the lab public route table and that table has an active 0.0.0.0/0 -> lab IGW route |
| ASG capacity | Live Min/Desired/Max equals 1/2/3 outside 09:00–11:00 UTC, and 2/3/4 within that time window |
| Scheduled scale-up | A recurring Auto Scaling scheduled action has recurrence `0 9 * * *`, UTC, and capacities 2/3/4 |
| Scheduled scale-down | A recurring scheduled action has recurrence `0 11 * * *`, UTC, and capacities 1/2/3 |

Note: the 09:00–11:00 UTC schedule is an explicit **proposed clarification** of the assessment wording (which currently does not specify time zone). Verify this matches your intended assessment before rollout.

## AWS Academy IAM prerequisite

The original stack has **no EC2 instance role**. The validator needs *read-only* credentials.
A new optional CloudFormation parameter `ValidationInstanceProfileArn` accepts the ARN of an **existing**, approved EC2 instance profile (not a role ARN), with at least:

- `ec2:DescribeSecurityGroups`
- `ec2:DescribeRouteTables`
- `autoscaling:DescribeAutoScalingGroups`
- `autoscaling:DescribeScheduledActions`

Learner Lab may restrict attaching instance profiles or `iam:PassRole`. **Do not broaden policies to circumvent lab restrictions.** Ask the account administrator to provide and approve an instance profile. Without it, the site may load but AWS checks show Fail; this is an **unavailable validation** rather than evidence that the student failed. Avoid deploying to students until this prerequisite is confirmed.

Run the stack with an approved profile by setting `export VALIDATION_INSTANCE_PROFILE_ARN=arn:aws:iam::<account-id>:instance-profile/<approved-profile-name>` before `bash run.sh`. The updated `run.sh` passes this parameter from the `VALIDATION_INSTANCE_PROFILE_ARN` environment variable, which defaults to empty. Without an approved profile, the new feature is **demonstration-only**. The stack retains normal provisioning without it.

## Deployment implementation

The Launch Template User Data downloads `validator/validator.py` from this review branch, configures a systemd service bound to `127.0.0.1:8765`, and adds an Apache reverse proxy for `/validation/`. Apache continues to host the existing PHP website on port 80. The validator is installed on **every** ASG instance.

**Before merging:** change the User Data download URL from `feature/self-validation-v1` to the stable main branch (or a release tag/commit). Pin to a reviewed commit for long-lived labs.

The validator is only used for self-checking; failures to install it do not block CloudFormation initialization. For a production-ready assessment, fail startup or expose a distinct validation-unavailable state and record validation service availability.

## Test checklist (must perform in AWS Academy before merging)

- [ ] Confirm the original AWS Academy app ZIP still downloads and Apache comes up.
- [ ] Confirm the AMI still supports yum, amazon-linux-extras and aws-cfn-bootstrap.
- [ ] Confirm validated IAM instance profile can be passed to EC2/ASG and Boto3 can call all four APIs.
- [ ] With deliberate 8080/route faults, validation page is unreachable externally; after repair, it loads.
- [ ] Confirm HTTP and routing checks switch Fail -> Pass without revealing fixes.
- [ ] Set ASG 1/2/3; confirm capacity Pass outside 09:00-11:00 UTC.
- [ ] Create both recurring actions; confirm each schedule check turns Pass.
- [ ] Test during 09:00-11:00 UTC with live 2/3/4 capacity.
- [ ] Confirm new ASG instances also serve `/validation/`.
- [ ] Delete stack using option 2; ensure no orphaned resources remain.
- [ ] Confirm permission errors and API outages are not mistaken for graded student failures.

## Known limitations

The HTTP check tests the local Apache site and its ingress rule, while the route check verifies configured public routing. It does not perform a public Internet HTTP probe. The schedule checker intentionally supports exactly daily UTC cron expressions. This MVP does not record grades, authenticate students, enforce SSL, or replace screenshots. A dedicated independent validator (Lambda or lecturer-hosted service) is preferable if feedback must remain available while the student breaks all web connectivity.
