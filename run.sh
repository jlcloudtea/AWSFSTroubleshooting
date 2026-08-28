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

      echo
      echo "You chose Create Troubleshooting Stack"
      echo "-------------------------------------------------------------"

      ############################################################
      # Check configured AWS region
      ############################################################

      REGION=$(aws configure get region)

      if [[ -z "$REGION" ]]; then

        REGION=$(aws ec2 describe-availability-zones \
          --query "AvailabilityZones[0].RegionName" \
          --output text 2>/dev/null)

      fi

      if [[ "$REGION" != "$REQUIRED_REGION" ]]; then

        echo
        echo "ERROR: This assessment must run in $REQUIRED_REGION."
        echo "Current region: $REGION"
        echo
        echo "Run:"
        echo
        echo "aws configure set region $REQUIRED_REGION"
        echo

        exit 1

      fi


      ############################################################
      # Check whether stack already exists
      ############################################################

      EXISTING_STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null)

      if [[ -n "$EXISTING_STACK_STATUS" && \
            "$EXISTING_STACK_STATUS" != "None" ]]; then

        echo
        echo "ERROR: CloudFormation stack '$STACK_NAME' already exists."
        echo "Current status: $EXISTING_STACK_STATUS"
        echo
        echo "Delete the existing stack before creating a new environment."
        echo

        exit 1

      fi


      ############################################################
      # Select two available Availability Zones
      #
      # These are intentionally NOT printed for students.
      ############################################################

      AZ1=$(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query "AvailabilityZones[0].ZoneName" \
        --output text)

      AZ2=$(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query "AvailabilityZones[1].ZoneName" \
        --output text)


      if [[ -z "$AZ1" || \
            "$AZ1" == "None" || \
            -z "$AZ2" || \
            "$AZ2" == "None" ]]; then

        echo
        echo "ERROR: At least two Availability Zones are required."
        exit 1

      fi


      ############################################################
      # Validate template before deployment
      ############################################################

      if ! aws cloudformation validate-template \
        --template-body "file://$TEMPLATE_FILE" \
        >/dev/null
      then

        echo
        echo "ERROR: CloudFormation template validation failed."
        exit 1

      fi


      ############################################################
      # Create stack
      ############################################################

      echo
      echo "-------------------------------------------------------------"
      echo " Creating Troubleshooting Environment"
      echo "-------------------------------------------------------------"
      echo
      echo "Creating AWS resources..."
      echo "This can take several minutes."
      echo


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


      ############################################################
      # Wait for CloudFormation.
      #
      # Because the YAML uses CreationPolicy + cfn-signal,
      # CREATE_COMPLETE now means UserData has completed.
      ############################################################

      echo "Waiting for EC2 and web server initialization..."
      echo


      if ! aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME"
      then

        echo
        echo "-------------------------------------------------------------"
        echo " Environment creation FAILED"
        echo "-------------------------------------------------------------"
        echo

        aws cloudformation describe-stack-events \
          --stack-name "$STACK_NAME" \
          --query \
          "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" \
          --output table

        echo
        echo "The environment was not created successfully."
        echo "Please contact your lecturer."
        echo

        exit 1

      fi


      ############################################################
      # Locate VPC
      ############################################################

      VPC_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query \
        "Stacks[0].Outputs[?OutputKey=='VPC'].OutputValue | [0]" \
        --output text)


      if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then

        echo
        echo "ERROR: Could not determine troubleshooting VPC."
        exit 1

      fi


      ############################################################
      # Locate route table
      ############################################################

      TRtable=$(aws ec2 describe-route-tables \
        --filters \
          "Name=tag:Name,Values=TR PublicRouteTable" \
          "Name=vpc-id,Values=$VPC_ID" \
        --query "RouteTables[0].RouteTableId" \
        --output text)


      ############################################################
      # Locate Internet Gateway
      ############################################################

      TRgw=$(aws ec2 describe-internet-gateways \
        --filters \
          "Name=tag:Name,Values=TroubleshootingGW" \
          "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query "InternetGateways[0].InternetGatewayId" \
        --output text)


      if [[ -z "$TRtable" || "$TRtable" == "None" ]]; then

        echo
        echo "ERROR: Could not locate troubleshooting route table."
        exit 1

      fi


      if [[ -z "$TRgw" || "$TRgw" == "None" ]]; then

        echo
        echo "ERROR: Could not locate troubleshooting Internet Gateway."
        exit 1

      fi


      ############################################################
      # INTENTIONAL TROUBLESHOOTING FAULT
      #
      # At this point:
      #
      #   - EC2 is running
      #   - UserData has completed
      #   - Apache has started
      #   - application files have downloaded
      #
      # Now deliberately break Internet routing.
      ############################################################

      if ! aws ec2 delete-route \
        --route-table-id "$TRtable" \
        --destination-cidr-block 0.0.0.0/0
      then

        echo
        echo "ERROR: Unable to prepare troubleshooting environment."
        exit 1

      fi


      if ! aws ec2 create-route \
        --route-table-id "$TRtable" \
        --destination-cidr-block 10.1.0.0/16 \
        --gateway-id "$TRgw" \
        >/dev/null
      then

        echo
        echo "ERROR: Unable to prepare troubleshooting environment."
        exit 1

      fi


      ############################################################
      # Locate EC2 instance
      ############################################################

      INSTANCE_ID=$(aws ec2 describe-instances \
        --filters \
          "Name=tag:Name,Values=Troubleshooting-server" \
          "Name=vpc-id,Values=$VPC_ID" \
          "Name=instance-state-name,Values=running" \
        --query \
          "Reservations[0].Instances[0].InstanceId" \
        --output text)


      if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then

        echo
        echo "ERROR: Could not locate troubleshooting EC2 instance."
        exit 1

      fi


      ############################################################
      # Student-facing output
      ############################################################

      echo
      echo "-------------------------------------------------------------"
      echo " Troubleshooting Environment Ready"
      echo "-------------------------------------------------------------"
      echo
      echo "Below is the information required for your assessment."
      echo


      echo "VPC Information"
      echo "-------------------------------------------------------------"

      aws ec2 describe-vpcs \
        --vpc-ids "$VPC_ID" \
        --query \
          "Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock}" \
        --output table


      echo
      echo "EC2 Instance Information"
      echo "-------------------------------------------------------------"

      aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query \
          "Reservations[].Instances[].{
            InstanceId:InstanceId,
            PrivateIpAddress:PrivateIpAddress,
            PublicIpAddress:PublicIpAddress
          }" \
        --output table


      echo
      echo "-------------------------------------------------------------"
      echo " You can now begin the troubleshooting assessment."
      echo "-------------------------------------------------------------"
      echo

      break
      ;;


    "Delete Troubleshooting Stack")

      echo
      echo "-------------------------------------------------------------"
      echo " Deleting Troubleshooting Environment"
      echo "-------------------------------------------------------------"
      echo


      ############################################################
      # Verify stack exists
      ############################################################

      STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null)


      if [[ -z "$STACK_STATUS" || "$STACK_STATUS" == "None" ]]; then

        echo "No '$STACK_NAME' CloudFormation stack exists."
        echo

        break

      fi


      ############################################################
      # Delete stack
      ############################################################

      if ! aws cloudformation delete-stack \
        --stack-name "$STACK_NAME"
      then

        echo
        echo "ERROR: Unable to start stack deletion."
        exit 1

      fi


      echo "Deleting AWS resources..."
      echo


      if aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME"
      then

        echo "-------------------------------------------------------------"
        echo " Troubleshooting Environment Deleted"
        echo "-------------------------------------------------------------"
        echo

      else

        echo
        echo "-------------------------------------------------------------"
        echo " Environment deletion FAILED"
        echo "-------------------------------------------------------------"
        echo

        aws cloudformation describe-stack-events \
          --stack-name "$STACK_NAME" \
          --query \
          "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" \
          --output table

        exit 1

      fi

      break
      ;;


    "Quit")

      echo
      echo "Exiting."
      break
      ;;


    *)

      echo
      echo "Invalid option: $REPLY"
      echo

      ;;

  esac

done
