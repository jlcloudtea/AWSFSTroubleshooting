#!/bin/bash

PS3='Please enter your choice or press 3 to quit: '
options=("Create Troubleshooting Stack" "Delete Troubleshooting Stack" "Quit")
select opt in "${options[@]}"
do
  case $opt in
	"Create Troubleshooting Stack")
	  echo "you chose choice 1"
	  echo '-------------------------------------------------------------'
	  echo ' 	Please wait 2-5 mins until new prompt message...     '
	  echo '-------------------------------------------------------------'
	  aws cloudformation create-stack --stack-name troubleshoot --template-body "file://TroubleshootingCLD401.yml" >/dev/null 2>&1
	  aws cloudformation wait stack-create-complete --stack-name troubleshoot
   	  sleep 70
	  TRtable=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=TR PublicRouteTable" "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=TroubleshootingVPC" --query "Vpcs[0].VpcId" --output text)" --query "RouteTables[0].RouteTableId" --output text)
	  TRgw=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=TroubleshootingGW" --query "InternetGateways[0].InternetGatewayId" --output text)
	  aws ec2 delete-route --route-table-id $TRtable --destination-cidr-block 0.0.0.0/0 >/dev/null 2>&1
	  aws ec2 create-route --route-table-id $TRtable --destination-cidr-block 10.10.0.0/16 --gateway-id $TRgw >/dev/null 2>&1
   	  echo '-------------------------------------------------------------'
	  echo '	Setup Completed You can start the troubleshooting    '
	  echo '-------------------------------------------------------------'
	  echo "Below is the related information for your reference"
	  aws cloudformation describe-stacks --stack-name troubleshoot --query "Stacks[*].Outputs[*].{OutputKey: OutputKey, OutputValue: OutputValue, Description: Description}" --output table
	  aws ec2 describe-instances --filter "Name=tag:Name,Values=Troubleshooting-server" --filters "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].{InstanceId:InstanceId, PrivateIpAddress:PrivateIpAddress, PublicIpAddress:PublicIpAddress}" --output table
	  break
	  ;;
	"Delete Troubleshooting Stack")
	  aws cloudformation delete-stack --stack-name troubleshoot
	  echo '-------------------------------------------------------------'
	  echo '	Deleting Troubleshooting Stack may takes 2-5 mins    '
	  echo '-------------------------------------------------------------'
	  break
	  ;;
	"Quit")
	  break
	  ;;
	*) echo "invalid option $REPLY";;
  esac
done
