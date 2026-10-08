#!/usr/bin/env python3
"""Read-only assessment checks; prints a link to the instance-hosted report page."""

import base64
import datetime as dt
import json
import subprocess
import sys
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo

STACK = "troubleshoot"
REGION = "us-east-1"
results = []


def aws(*args):
    process = subprocess.run(
        ["aws", *args, "--region", REGION, "--output", "json"],
        capture_output=True, text=True, timeout=30,
    )
    if process.returncode:
        raise RuntimeError((process.stderr or process.stdout).strip()[:300])
    return json.loads(process.stdout)


def record(label, passed, detail):
    results.append({"label": label, "passed": bool(passed), "detail": detail})
    print(f"{'PASS' if passed else 'FAIL'}  {label}: {detail}")


def resource(logical_id):
    data = aws("cloudformation", "describe-stack-resource", "--stack-name", STACK,
               "--logical-resource-id", logical_id)
    return data["StackResourceDetail"]["PhysicalResourceId"]


def permission_allows_http(permission):
    if permission.get("IpProtocol") not in ("tcp", "-1"):
        return False
    if permission.get("IpProtocol") == "tcp":
        if not (permission.get("FromPort", 65536) <= 80 <= permission.get("ToPort", -1)):
            return False
    return any(item.get("CidrIp") == "0.0.0.0/0"
               for item in permission.get("IpRanges", []))


def schedule_matches(action, hour, sizes):
    recurrence = action.get("Recurrence", "")
    return (recurrence.split() == ["0", str(hour), "*", "*", "*"]
            and (action.get("MinSize"), action.get("DesiredCapacity"),
                 action.get("MaxSize")) == sizes
            and not action.get("EndTime"))


def main():
    try:
        route_table = resource("PublicRouteTable")
        gateway = resource("InternetGateway")
        group_id = resource("InstanceSecurityGroup")
        asg_name = resource("AutoScalingGroup")
    except (RuntimeError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"Cannot inspect stack '{STACK}' in {REGION}: {error}", file=sys.stderr)
        return 2

    public_ip = None
    report_path = None
    try:
        routes = aws("ec2", "describe-route-tables", "--route-table-ids", route_table)
        route = next((r for r in routes["RouteTables"][0]["Routes"]
                      if r.get("DestinationCidrBlock") == "0.0.0.0/0"), {})
        record("Public route", route.get("GatewayId") == gateway
               and route.get("State") == "active",
               "0.0.0.0/0 points to the lab Internet Gateway"
               if route.get("GatewayId") == gateway and route.get("State") == "active"
               else "Default route to the lab Internet Gateway is missing or inactive")
    except (RuntimeError, KeyError, IndexError, subprocess.TimeoutExpired) as error:
        record("Public route", False, f"Could not inspect route: {error}")

    try:
        groups = aws("ec2", "describe-security-groups", "--group-ids", group_id)
        allowed = any(permission_allows_http(p)
                      for p in groups["SecurityGroups"][0]["IpPermissions"])
        record("HTTP security group", allowed,
               "TCP 80 is open to 0.0.0.0/0" if allowed
               else "TCP 80 is not open to 0.0.0.0/0")
    except (RuntimeError, KeyError, IndexError, subprocess.TimeoutExpired) as error:
        record("HTTP security group", False, f"Could not inspect security group: {error}")

    try:
        data = aws("autoscaling", "describe-auto-scaling-groups",
                   "--auto-scaling-group-names", asg_name)
        group = data["AutoScalingGroups"][0]
        scheduled = aws("autoscaling", "describe-scheduled-actions",
                        "--auto-scaling-group-name", asg_name)["ScheduledUpdateGroupActions"]
        morning = [a for a in scheduled if schedule_matches(a, 9, (2, 3, 4))]
        evening = [a for a in scheduled if schedule_matches(a, 11, (1, 2, 3))]
        same_zone = bool(morning and evening and
                         (morning[0].get("TimeZone") or "UTC") ==
                         (evening[0].get("TimeZone") or "UTC"))
        zone = (morning[0].get("TimeZone") or "UTC") if same_zone else "UTC"
        record("Daily 09:00–11:00 schedule", same_zone,
               f"09:00 → 2/3/4 and 11:00 → 1/2/3 ({zone}); no end dates" if same_zone
               else "Expected two daily actions at 09:00 and 11:00 with the same time zone and no end dates")

        try:
            hour = dt.datetime.now(ZoneInfo(zone)).hour
        except (KeyError, ValueError):
            hour = dt.datetime.now(dt.timezone.utc).hour
        expected = (2, 3, 4) if same_zone and 9 <= hour < 11 else (1, 2, 3)
        actual = (group["MinSize"], group["DesiredCapacity"], group["MaxSize"])
        record("Auto Scaling capacity", actual == expected,
               f"Current min/desired/max: {actual[0]}/{actual[1]}/{actual[2]}; "
               f"expected {expected[0]}/{expected[1]}/{expected[2]}")

        instance_ids = [i["InstanceId"] for i in group["Instances"]
                        if i.get("LifecycleState") == "InService"]
        if instance_ids:
            instances = aws("ec2", "describe-instances", "--instance-ids", *instance_ids)
            for reservation in instances["Reservations"]:
                for instance in reservation["Instances"]:
                    if instance.get("PublicIpAddress"):
                        public_ip = instance["PublicIpAddress"]
                        break
                if public_ip:
                    break
    except (RuntimeError, KeyError, IndexError, subprocess.TimeoutExpired) as error:
        record("Daily 09:00–11:00 schedule", False, f"Could not inspect actions: {error}")
        record("Auto Scaling capacity", False, "Could not inspect group capacity")

    if public_ip:
        try:
            with urllib.request.urlopen(f"http://{public_ip}/", timeout=5) as response:
                reachable = 200 <= response.status < 400
                status = response.status
                homepage = response.read(65536).decode("utf-8", errors="replace")
            record("Public HTTP response", reachable, f"http://{public_ip}/ returned HTTP {status}")
            if reachable:
                if 'id="summary"' in homepage:
                    report_path = "/"
                else:
                    try:
                        with urllib.request.urlopen(
                            f"http://{public_ip}/verification.html", timeout=5
                        ) as response:
                            alternate = response.read(65536).decode("utf-8", errors="replace")
                            if 200 <= response.status < 400 and 'id="summary"' in alternate:
                                report_path = "/verification.html"
                    except (urllib.error.URLError, TimeoutError, OSError):
                        pass
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            record("Public HTTP response", False, f"Could not load http://{public_ip}/: {error}")
    else:
        record("Public HTTP response", False, "No in-service instance with a public IP was found")

    passed = sum(r["passed"] for r in results)
    print(f"\nResult: {passed}/{len(results)} checks passed.")
    if public_ip and report_path:
        payload = {"version": 1, "stack": STACK, "region": REGION,
                   "checkedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                   "results": results}
        token = base64.urlsafe_b64encode(
            json.dumps(payload, separators=(",", ":")).encode()
        ).decode().rstrip("=")
        print("\nOpen the web page with this report link after HTTP access works:")
        print(f"http://{public_ip}{report_path}#{token}")
        print("This is feedback for practice, not a tamper-proof grading record.")
    elif public_ip:
        print("\nThe web server responded, but no verification page was found on this instance.")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
