#!/usr/bin/env python3
"""Read-only lab validation API. Python stdlib HTTP server + boto3.
Never accepts AWS resource identifiers or AWS actions from HTTP requests.
"""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import boto3

REGION = os.environ.get("AWS_REGION", "us-east-1")
SG_ID = os.environ["LAB_SECURITY_GROUP_ID"]
ROUTE_TABLE_ID = os.environ["LAB_ROUTE_TABLE_ID"]
IGW_ID = os.environ["LAB_IGW_ID"]
ASG_NAME = os.environ["LAB_ASG_NAME"]
SUBNET_IDS = os.environ["LAB_SUBNET_IDS"].split(",")
PORT = int(os.environ.get("VALIDATOR_PORT", "8765"))

LABELS = [
    "1. HTTP web server access",
    "2. Public subnet Internet routing",
    "3. Auto Scaling capacity (1 / 2 / 3)",
    "4. Daily scale-up at 09:00 UTC (2 / 3 / 4)",
    "5. Daily scale-down at 11:00 UTC (1 / 2 / 3)",
]

def schedule_matches(action, minute, hour, minimum, desired, maximum):
    recurrence = " ".join((action.get("Recurrence") or "").split())
    return (
        recurrence == f"{minute} {hour} * * *"
        and action.get("MinSize") == minimum
        and action.get("DesiredCapacity") == desired
        and action.get("MaxSize") == maximum
        and action.get("TimeZone", "UTC") == "UTC"
    )

def verify():
    outcomes = [False] * 5
    try:
        ec2 = boto3.client("ec2", region_name=REGION)
        sg = ec2.describe_security_groups(GroupIds=[SG_ID])["SecurityGroups"][0]
        def allows_http(rule):
            if rule.get("IpProtocol") not in ("tcp", "-1"):
                return False
            if rule.get("IpProtocol") == "tcp" and not (
                rule.get("FromPort", 65536) <= 80 <= rule.get("ToPort", -1)
            ):
                return False
            return any(r.get("CidrIp") == "0.0.0.0/0" for r in rule.get("IpRanges", []))
        allowed = any(allows_http(rule) for rule in sg.get("IpPermissions", []))
        try:
            with urllib.request.urlopen("http://127.0.0.1/", timeout=3) as response:
                web_ok = response.status == 200
        except Exception:
            web_ok = False
        outcomes[0] = allowed and web_ok

        route_tables = ec2.describe_route_tables(RouteTableIds=[ROUTE_TABLE_ID])["RouteTables"]
        rt = route_tables[0]
        has_default = any(
            r.get("DestinationCidrBlock") == "0.0.0.0/0"
            and r.get("GatewayId") == IGW_ID
            and r.get("State", "active") == "active"
            for r in rt.get("Routes", [])
        )
        associated = {
            a.get("SubnetId") for a in rt.get("Associations", []) if a.get("SubnetId")
        }
        outcomes[1] = has_default and set(SUBNET_IDS).issubset(associated)
    except Exception:
        pass

    try:
        asc = boto3.client("autoscaling", region_name=REGION)
        groups = asc.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])["AutoScalingGroups"]
        if groups:
            group = groups[0]
            outcomes[2] = (group["MinSize"],group["DesiredCapacity"],group["MaxSize"]) == (1,2,3)
        actions = asc.describe_scheduled_actions(AutoScalingGroupName=ASG_NAME).get("ScheduledUpdateGroupActions", [])
        outcomes[3] = any(schedule_matches(a,0,9,2,3,4) for a in actions)
        outcomes[4] = any(schedule_matches(a,0,11,1,2,3) for a in actions)
    except Exception:
        pass
    return [{"name": name, "pass": passed} for name, passed in zip(LABELS, outcomes)]

PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Erfys Confectionary | Validation</title>
<style>
body{font:16px system-ui,sans-serif;margin:0;background:#f2f3f3;color:#17212e}
header{background:#232f3e;color:white;padding:18px 24px;font-weight:700}
main{max-width:820px;margin:40px auto;padding:0 18px}
section{background:white;border:1px solid #d5dbdb;border-radius:8px;padding:20px;margin-bottom:16px}
h1{font-size:25px}button{padding:10px 20px;cursor:pointer}
table{width:100%;border-collapse:collapse}td{padding:14px 6px;border-bottom:1px solid #eee}
td:last-child{text-align:right}.pass{color:#037f0c;font-weight:bold}.fail{color:#b42318;font-weight:bold}
meter{width:100%;height:18px}
</style></head><body><header>Erfys Confectionary — Troubleshooting Lab</header>
<main><h1>Challenge Validation</h1><p>Pass / Fail only — investigate failed checks independently.</p>
<section><h2 id="count">Checking...</h2><meter id="progress" min="0" max="5" value="0"></meter>
<p><button onclick="refresh()">Refresh checks</button></p></section>
<section><table aria-label="Challenge validation results"><tbody id="results"></tbody></table></section>
<p>These live checks are formative feedback, not a replacement for assessment evidence.</p>
</main><script>
async function refresh(){
 const btn=document.querySelector("button");btn.disabled=true;
 document.getElementById("count").textContent="Checking...";
 try{
  const response=await fetch("api",{cache:"no-store"});
  if(!response.ok)throw new Error("Unavailable");
  const items=await response.json();
  const count=items.filter(x=>x.pass).length;
  document.getElementById("count").textContent=count+" of "+items.length+" completed";
  const progress=document.getElementById("progress");progress.max=items.length;progress.value=count;
  const tbody=document.getElementById("results");tbody.replaceChildren();
  for(const item of items){
   const row=document.createElement("tr"),name=document.createElement("td"),status=document.createElement("td");
   name.textContent=item.name;status.textContent=item.pass?"Pass":"Fail";
   status.className=item.pass?"pass":"fail";row.append(name,status);tbody.append(row);
  }
 }catch(e){document.getElementById("count").textContent="Validation unavailable";}
 finally{btn.disabled=false;}
}
refresh();
</script></body></html>"""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path.rstrip("/")
        if path in ("", "/validation"):
            payload, content_type = PAGE.encode(), "text/html; charset=utf-8"
        elif path == "/validation/api":
            payload, content_type = json.dumps(verify()).encode(), "application/json"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type",content_type)
        self.send_header("Cache-Control","no-store")
        self.send_header("Content-Length",str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1",PORT),Handler).serve_forever()
