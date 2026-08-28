#!/bin/bash

STACK_NAME="troubleshoot"
TEMPLATE_FILE="TroubleshootingCLD401.yml"
REQUIRED_REGION="us-east-1"

PS3='Please enter your choice or press 3 to quit: '

options=(
  "Create Troubleshooting Stack"
  "Delete Troubleshooting Stack"
  "Quit"
)

select opt in "${options[@]}"
do
  case $opt in

    "Create Troubleshooting Stack")

      echo "You chose Create Troubleshooting Stack"
      echo '-------------------------------------------------------------'

      #
      # Check AWS region
      #
      REGION=$(aws configure get region)

      if [[ -z "$REGION" ]]; then
        REGION=$(aws ec2 describe-availability-zones \
          --query "AvailabilityZones[0].RegionName" \
          --output text 2>/dev/null)
      fi

      echo "Current AWS region: $REGION"

      if [[ "$REGION" != "$REQUIRED_REGION" ]]; then
        echo
        echo "ERROR: This lab must run in $REQUIRED_REGION"
        echo "Current region: $REGION"
        echo
        echo "Run:"
        echo "aws configure set region $REQUIRED_REGION"
        exit 1
      fi

      #
      # Dynamically select two available AZs.
      # Do NOT use default subnets / Fn::GetAZs.
      #
      AZ1=$(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query "AvailabilityZones[0].ZoneName" \
        --output text)

      AZ2=$(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query "AvailabilityZones[1].ZoneName" \
        --output text)

      if [[ -z "$AZ1" || "$AZ1" == "None" || \
            -z "$AZ2" || "$AZ2" == "None" ]]; then

        echo "ERROR: At least two available Availability Zones are required."
        exit 1
      fi

      echo
      echo "Selected Availability Zones:"
      echo "Subnet 1: $AZ1"
      echo "Subnet 2: $AZ2"
      echo

      echo '-------------------------------------------------------------'
      echo ' Creating CloudFormation stack... '
      echo '-------------------------------------------------------------'

      #
      # Create CloudFormation stack
      #
      if ! aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
          ParameterKey=AvailabilityZone1,ParameterValue="$AZ1" \
          ParameterKey=AvailabilityZone2,ParameterValue="$AZ2" \
        >/dev/null
      then
        echo
        echo "ERROR: Unable to start CloudFormation stack creation."
        exit 1
      fi

      echo
      echo "Waiting for stack creation to complete..."

      #
      # Wait for stack
      #
      if ! aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME"
      then

        echo
        echo '-------------------------------------------------------------'
        echo ' CloudFormation stack creation FAILED '
        echo '-------------------------------------------------------------'
        echo
        echo "Failed resources:"
        echo

        aws cloudformation describe-stack-events \
          --stack-name "$STACK_NAME" \
          --query \
          "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" \
          --output table

        exit 1
      fi

      echo
      echo '-------------------------------------------------------------'
      echo ' CloudFormation creation completed '
      echo '-------------------------------------------------------------'

      #
      # Allow resources to settle before intentionally
      # modifying the route table for the troubleshooting lab
      #
      sleep 70

      #
      # Find troubleshooting route table
      #
      VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=TroubleshootingVPC" \
        --query "Vpcs[0].VpcId" \
        --output text)

      TRtable=$(aws ec2 describe-route-tables \
        --filters \
          "Name=tag:Name,Values=TR PublicRouteTable" \
          "Name=vpc-id,Values=$VPC_ID" \
        --query "RouteTables[0].RouteTableId" \
        --output text)

      #
      # Find Internet Gateway
      #
      TRgw=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=TroubleshootingGW" \
        --query "InternetGateways[0].InternetGatewayId" \
        --output text)

      if [[ "$TRtable" == "None" || -z "$TRtable" ]]; then
        echo "ERROR: Could not locate troubleshooting route table."
        exit 1
      fi

      if [[ "$TRgw" == "None" || -z "$TRgw" ]]; then
        echo "ERROR: Could not locate troubleshooting Internet Gateway."
        exit 1
      fi

      #
      # INTENTIONAL TROUBLESHOOTING FAULT
      #
      # Delete normal Internet route
      #
      aws ec2 delete-route \
        --route-table-id "$TRtable" \
        --destination-cidr-block 0.0.0.0/0

      #
      # Add incorrect route intentionally
      #
      aws ec2 create-route \
        --route-table-id "$TRtable" \
        --destination-cidr-block 10.1.0.0/16 \
        --gateway-id "$TRgw" \
      >/dev/null

      echo
      echo '-------------------------------------------------------------'
      echo ' Setup Completed - You can start troubleshooting '
      echo '-------------------------------------------------------------'
      echo
      echo "Below is the related information for your reference"

      aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query \
        "Stacks[*].Outputs[*].{OutputKey:OutputKey,OutputValue:OutputValue,Description:Description}" \
        --output table

      aws ec2 describe-instances \
        --filters \
          "Name=tag:Name,Values=Troubleshooting-server" \
          "Name=instance-state-name,Values=running" \
        --query \
        "Reservations[].Instances[].{InstanceId:InstanceId,PrivateIpAddress:PrivateIpAddress,PublicIpAddress:PublicIpAddress,AZ:Placement.AvailabilityZone}" \
        --output table

      break
      ;;

    "Delete Troubleshooting Stack")

      echo
      echo '-------------------------------------------------------------'
      echo ' Deleting Troubleshooting Stack '
      echo '-------------------------------------------------------------'

      aws cloudformation delete-stack \
        --stack-name "$STACK_NAME"

      echo "Waiting for deletion..."

      if aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME"
      then
        echo
        echo "Stack deleted successfully."
      else
        echo
        echo "ERROR: Stack deletion failed."
        echo
        echo "Recent CloudFormation events:"

        aws cloudformation describe-stack-events \
          --stack-name "$STACK_NAME" \
          --max-items 10 \
          --output table
      fi

      break
      ;;

    "Quit")
      break
      ;;

    *)
      echo "Invalid option: $REPLY"
      ;;

  esac
done
