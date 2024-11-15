#!/bin/bash

# Initialize variables
FUNCTIONS="connect | upload | download"
profile_name=""
ssh_user="ec2-user"
port_forward=""
path_file=""
directory=""
ssh_public="$HOME/.ssh/id_rsa.pub"
ssh_private="$HOME/.ssh/id_rsa"
output=""


print_usage () {
    echo "
Usage: $(basename $0) [OPTIONS]

Options:
  help                  Help options to the script
  -c [connector]        <required |     always      >      Type of connection [ connect (SSH) | download (SCP) | upload (SCP) ]
  -p [profile]          <required |     always      >      AWS profile used [Get from ~/.aws/config]
  -f [port forward]     <optional |     connect     >      Use to port forward from Remote to Local
  -l [path]             <required | download/upload >      The file location that should be download/upload 
  -u [user]             <optional |       all       >      SSH User [Default to ec2-user]
  -s [ssh public key]   <optional |       all       >      Use to overide the default public key [\$HOME/.ssh/id_rsa.pub]
  -t [ssh private key]  <optional |       all       >      Use to overide the default private key [\$HOME/.ssh/id_rsa]
  -d [directory]        <optional | download/upload >      Use when you want to upload/download a directory [Only accepts \"dir\" as the value]
  -o [directory]        <optional | download/upload >      Use to overide the default file save location for download/upload [~/]
"
}

print_connect_usage () {
echo "
Usage: $(basename $0) [CONNECT OPTIONS]

Options:
  help                  Help options to the script
  -c [connector]        <required |     always      >      Type of connection [ connect (SSH) | download (SCP) | upload (SCP) ]
  -p [profile]          <required |     always      >      AWS profile used [Get from ~/.aws/config]
  -u [user]             <optional |       all       >      SSH User [Default to ec2-user]
  -f [port forward]     <optional |     connect     >      Use to port forward from Remote to Local
  -s [ssh public key]   <optional |       all       >      Use to overide the default public key [\$HOME/.ssh/id_rsa.pub]
  -t [ssh private key]  <optional |       all       >      Use to overide the default private key [\$HOME/.ssh/id_rsa]
"
}

print_other_usage () {
echo "
Usage: $(basename $0) [DOWNLOAD/UPLOAD OPTIONS]

Options:
  help                  Help options to the script
  -c [connector]        <required |     always      >      Type of connection [ connect (SSH) | download (SCP) | upload (SCP) ]
  -p [profile]          <required |     always      >      AWS profile used [Get from ~/.aws/config]
  -u [user]             <optional |       all       >      SSH User [Default to ec2-user]
  -l [path]             <required | download/upload >      The file location that should be download/upload 
  -s [ssh public key]   <optional |       all       >      Use to overide the default public key [\$HOME/.ssh/id_rsa.pub]
  -t [ssh private key]  <optional |       all       >      Use to overide the default private key [\$HOME/.ssh/id_rsa]
  -d [directory]        <optional | download/upload >      Use when you want to upload/download a directory [Only accepts \"dir\" as the value]
  -o [directory]        <optional | download/upload >      Use to overide the default file save location for download/upload [~/]
"
}

if [ "$1" == "help" ];
then
  print_usage
  exit 1
fi

# Parse the input arguments
while getopts "c:p:u:f:l:d:s:t:o:" flag; do
  case "$flag" in
    c) connector=$OPTARG ;;
    p) profile_name=$OPTARG ;;
    u) ssh_user=$OPTARG ;;
    f) port_forward=$OPTARG ;;
    l) path_file=$OPTARG ;;
    d) directory=$OPTARG ;;
    s) ssh_public=$OPTARG ;;
    t) ssh_private=$OPTARG ;;
    o) output=$OPTARG ;;
    *) echo "Invalid option: -$flag" && print_usage && exit 1;;
  esac
done

if [ -z "$profile_name" ] || [ -z "$connector" ];
then
  print_usage
  exit 1
fi

case $connector in
    connect)
        if [[ ! -z "$path_file" ]] || [[ ! -z "$directory" ]] || [[ ! -z "$output" ]]
        then 
            print_connect_usage
            exit 1
        fi
    ;;
    download)
        [[ -z "$output" ]] && output="$HOME"
        if [[ -z "$path_file" ]] || [[ ! -z "$port_forward" ]]
        then 
            [[ -z "$path_file" ]] && echo "Missing -l"
            [[ -z "$port_forward" ]] && echo "Should not exist -f"
            print_other_usage
            exit 1
        fi
    ;;  
    upload)
        [[ -z "$output" ]] && output="~/"
        if [[ -z "$path_file" ]] || [[ ! -z "$port_forward" ]]
        then 
            [[ -z "$path_file" ]] && echo "Missing -l"
            [[ -z "$port_forward" ]] && echo "Should not exist -f"
            print_other_usage
            exit 1
        fi
    ;;
    *)
        print_usage
        exit 1
    ;;
esac

aws s3 --profile $profile_name ls > /dev/null || aws sso login --profile $profile_name

RESULT=$(aws --profile $profile_name ec2 describe-instances --filter "Name=instance-state-name,Values=running")

INSTANCE_NAME=$(echo $RESULT | jq '.Reservations[].Instances[] | (.Tags[]? | select(.Key == "Name") | .Value) // .InstanceId')

# Loop through each instance name
while IFS= read -r item; do
    # Trim quotes and whitespace
    INSTANCES=$(echo "$item" | tr -d '"')

    # Find the private IP address using jq
    PRIVATE_IP=$(echo "$RESULT" | jq -r ".Reservations[].Instances[] | select((.Tags[] | select(.Key == \"Name\" and .Value == \"$INSTANCES\")) // select(.InstanceId == \"$INSTANCES\")) | .NetworkInterfaces[].PrivateIpAddress")

    # If multiple IPs, join them with commas
    PRIVATE_IP=$(echo "$PRIVATE_IP" | tr '\n' ',' | sed 's/,$//')

    # Format the instance and IP
    INSTANCE_W_IP="$INSTANCES:$PRIVATE_IP"

    # Append to STRINGS
    STRINGS+="$INSTANCE_W_IP"$'\n'
done <<< "$INSTANCE_NAME"

# Convert STRINGS to an array using newline as delimiter
IFS=$'\n' read -r -d '' -a choices <<< "$STRINGS"

exiting () {
    >/dev/stderr echo "Remove public key ${DEFAULT_SSH_PUBLIC} for $ssh_user at instance ${INSTANCE}"
    aws ssm send-command --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"grep -v '$SSH_KEY' /home/$ssh_user/.ssh/authorized_keys > /home/$ssh_user/.ssh/authorized_keys.tmp && mv /home/$ssh_user/.ssh/authorized_keys /home/$ssh_user/.ssh/authorized_keys.bak&& mv /home/$ssh_user/.ssh/authorized_keys.tmp /home/$ssh_user/.ssh/authorized_keys && rm -rf /home/$ssh_user/.ssh/authorized_keys.bak && chown $ssh_user:$ssh_user /home/$ssh_user/.ssh/authorized_keys && chmod 600 /home/$ssh_user/.ssh/authorized_keys\"]" \
        --targets "Key=instanceids,Values=$INSTANCE" \
        --comment "Add SSH Key" \
        --profile $profile_name > /dev/null

    grep -v "$instance_name" ~/.ssh/known_hosts > ~/.ssh/known_hosts
}

connect() {
    if [[ -z $port_forward ]]; then
        ssh -i $ssh_private -o ProxyCommand="$AWS_COMMAND" $ssh_user@$instance_name
    else
        ssh -L $port_forward -i $ssh_private -o ProxyCommand="$AWS_COMMAND" $ssh_user@$instance_name
    fi
}

upload () {
    if [ -z "$path_file" ];
    then
        echo "No File Path Provided"
        exiting
        exit 1
    fi

    if [[ -z $directory ]]; then 
        scp -i $ssh_private -o ProxyCommand="$AWS_COMMAND" $path_file $ssh_user@$instance_name:$output
    else
        if [ "$directory" == "dir" ]; then
            scp -i $ssh_private -o ProxyCommand="$AWS_COMMAND" -r $path_file $ssh_user@$instance_name:$output
        else
            echo "Directory can only be dir not $directory"
            exiting
        fi
    fi
}

download () {
    if [ -z "$path_file" ];
    then
        echo "No File Path Provided"
        exiting
    fi

    if [[ -z $directory ]]; then 
        scp -i $ssh_private -o ProxyCommand="$AWS_COMMAND" $ssh_user@$instance_name:$path_file $output        
    else
        if [ "$directory" == "dir" ]; then
            scp -i $ssh_private -o ProxyCommand="$AWS_COMMAND" -r $ssh_user@$instance_name:$path_file $output
        else
            echo "Directory can only be dir not $directory"
            exiting
        fi
    fi
    
}

select choice in "${choices[@]}"
    do
        case $choice in
        "$choice")
            if [[ -z $choice ]]; then
                echo "Invalid choice. Please retry and select a valid option."
                break
            fi

            instance_name=$(echo "$choice" | cut -d: -f1)

            INSTANCE_ID=$(echo $RESULT | jq ".Reservations[].Instances[] | select((.Tags[] | select(.Key == \"Name\" and .Value == \"$instance_name\")) // select(.InstanceId == \"$instance_name\")) | .InstanceId")

            INSTANCE=$(echo "$INSTANCE_ID" | tr -d '"')

            SSH_KEY="$(cat $ssh_public)"

            AWS_COMMAND="aws ssm start-session --target $INSTANCE --profile $profile_name --document-name AWS-StartSSHSession --parameters portNumber=%p"

            >/dev/stderr echo "Add public key ${ssh_public} for $ssh_user at instance ${INSTANCE}"
            aws ssm send-command --document-name "AWS-RunShellScript" \
                --parameters "commands=[\"grep -qxF '$SSH_KEY' /home/$ssh_user/.ssh/authorized_keys || echo $SSH_KEY >> /home/$ssh_user/.ssh/authorized_keys\"]" \
                --targets "Key=instanceids,Values=$INSTANCE" \
                --comment "Add SSH Key" \
                --profile $profile_name > /dev/null

            if [[ " $FUNCTIONS " =~ .*\ $connector\ .* ]]; then
                $connector
                
                exiting
            else
                echo "Wrong option" $1 "should be one of" $FUNCTIONS
            fi

            break
            ;;
        *)
    esac
done
