#!/bin/bash

PS3='Please enter your choice or press 3 to quit: '
options=("Create Troubleshooting Stack" "Delete Troubleshooting Stack" "Quit")
select opt in "${options[@]}"
do
  case $opt in
	"Create Troubleshooting Stack")
	  echo "you chose choice 1"
	  echo '-------------------------------------------------------------'
	  echo ' 	Please wait 2-5 mins until new prompt message...         '
	  echo '-------------------------------------------------------------'
	  aws cloudformation create-stack --stack-name troubleshoot --template-body "file://TroubleshootingCLD401.yml" >/dev/null 2>&1
	  aws cloudformation wait stack-create-complete --stack-name troubleshoot
	  echo '-------------------------------------------------------------'
	  echo '	Setup Completed You can start the troubleshooting       '
	  echo '-------------------------------------------------------------'
	  echo "Debug-Below are the related information for your reference"
	  aws cloudformation describe-stacks --stack-name troubleshoot --query "Stacks[*].Outputs[*].{OutputKey: OutputKey, OutputValue: OutputValue, Description: Description}" --output table
	  break
	  ;;
	"Delete Troubleshooting Stack")
	  aws cloudformation delete-stack --stack-name troubleshoot
	  echo '-------------------------------------------------------------'
	  echo '	Deleting Troubleshooting Stack may takes 2-5 mins 	   '
	  echo '-------------------------------------------------------------'
	  break
	  ;;
	"Quit")
	  break
	  ;;
	*) echo "invalid option $REPLY";;
  esac
done