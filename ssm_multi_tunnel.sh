#!/bin/bash

# Help text
help()
{
    echo ""
    echo "          -o | --override               Override port forwarding values."
    echo "                                        Syntax:[socks port]"
    echo ""
}

# Set variables. These can be overwritten with the -o option.
###########################
#### Socks Proxy vars #####
###########################
SOCKSPort="1080"
########################
#### Port FWD vars #####
########################
localPort="8000"
remotePort="80"
########################
###### Other vars ######
########################
AWS_DEFAULT_REGION='cn-north-1'
ssmUser="ec2-user"
ssmDoc="AWS-StartPortForwardingSession"

# Get parameters
while [[ $1 != "" ]]
do
    case $1 in
        -s | --socks  )            override=true
                                    shift
                                    SOCKSPort=$1
                                    ;;
        -f | --portfwd  )          override=true
                                    shift
                                    localPort=$1
                                    shift
                                    remoteHost=$1
                                    shift
                                    remotePort=$1
                                    ;;
        -h | --help )               help
                                    exit
                                    ;;
        * )                         help
                                    exit 1
    esac
    shift
done

function checkDependencies {
    errorMessages=()

    echo -ne "Checking dependencies..................\r"

    # Check AWS CLI
    aws=$(aws --version 2>&1)
    if [[ $? != 0 ]]; then
        errorMessages+=('AWS CLI not found. Please install the latest version of AWS CLI.')
    else
        minVersion="2.1.20"
        version=$(echo $aws | cut -d' ' -f 1 | cut -d'/' -f 2)

        for i in {1..3}
        do
            x=$(echo "$version" | cut -d '.' -f $i)
            y=$(echo "$minVersion" | cut -d '.' -f $i)
            if [[ $x < $y ]]; then
                errorMessages+=('Installed version of AWS CLI does not meet minimum version. Please install the latest version of AWS CLI.')
                break
            fi
        done
    fi

    # Check Session Manager Plugin
    ssm=$(session-manager-plugin --version 2>&1)
    if [[ $? != 0 ]]; then
        errorMessages+=('AWS Session Manager Plugin not found. Please install the latest version of AWS Session Manager Plugin.')
    fi

    # If there are any error messages, print them and exit.
    if [[ $errorMessages ]]; then
        echo -ne "Checking dependencies..................Error"
        echo -ne "\n"
        for errorMessage in "${errorMessages[@]}"
        do
            echo "Failed dependency check"
            echo "======================="
            echo " - ${errorMessage}"
        done
        exit
    fi

    echo -ne "Checking dependencies..................Done"
    echo -ne "\n"
}

function setInstanceIdandAz {
    # Get random running instance with ServerRole:JumpServers tag
    echo -ne "Getting available jump instance........\r"
    result=$(aws ec2 describe-instances --filter "Name=tag:ServerRole,Values=JumpServers" --query "Reservations[].Instances[?State.Name == 'running'].{Id:InstanceId, Az:Placement.AvailabilityZone}[]" --output text)

    if [[ $result ]]; then
        azs=($(echo "$result" | cut -d $'\t' -f 1))
        instances=($(echo "$result" | cut -d $'\t' -f 2))
        
        instancesLength="${#instances[@]}"
        randomInstance=$(( $RANDOM % $instancesLength ))

        instanceId="${instances[$randomInstance]}"
        az="${azs[$randomInstance]}"
        echo -ne "Getting available jump instance........Done"
        echo -ne "\n"
    else
        echo "Could not find a running jump server. Please try again."
        exit
    fi 
}

function loadSSHKey {
    echo $AWS_DEFAULT_REGION
    if [[ $AWS_DEFAULT_REGION != "cn-north-1" ]] && [[ $AWS_DEFAULT_REGION != "cn-northwest-1" ]]; then
        # Generate SSH key
        echo -ne "Generating SSH key pair................\r"
        echo -e 'y\n' | ssh-keygen -t rsa -f temp -N '' > /dev/null 2>&1
        echo -ne "Generating SSH key pair................Done"
        echo -ne "\n"

        # Push SSH key to instance
        echo -ne "Pushing public key to instance.........\r"
        aws ec2-instance-connect send-ssh-public-key --region $AWS_DEFAULT_REGION --instance-id $instanceId --availability-zone $az --instance-os-user $ssmUser --ssh-public-key file://temp.pub > /dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -ne "Pushing public key to instance.........Error"
            echo -ne "\n"
            exit
        fi
        echo -ne "Pushing public key to instance.........Done"
        echo -ne "\n"
    else
        cp -f $KEYPAIR ./temp.pem
    fi
}


function SSMPortForward {
    local remotePort="$1"
    local localPort="$2"
   # Start SSM session with port forwarding enabled listening locally 
   echo -ne "Starting SSM Port Forwarding (local port:$localPort).........\r"
   aws ssm start-session --target $instanceId --document-name $ssmDoc --parameters "{\"portNumber\":[\"$remotePort\"],\"localPortNumber\":[\"$localPort\"]}" --region $AWS_DEFAULT_REGION &

    if [[ $? != 0 ]]; then
        echo -ne "Starting SSM Port Forwarding.........Error"
        echo -ne "\n"
        exit
    fi
    echo -ne "Starting SSM Port Forwarding.........Done"
    echo -ne "\n"
}

function SSHSockProxy {
   # Start SSH Socks proxy
   echo -ne "Starting SSH Socks proxy to port $SOCKSPort.........\r"
   ssh -f -N -p 2200 -i temp -o "IdentitiesOnly=yes" -D $SOCKSPort ec2-user@localhost
    if [[ $? != 0 ]]; then
        echo -ne "Starting SSH Socks proxy to port $SOCKSPort.........Error"
        echo -ne "\n"
        exit
    fi
    echo -ne "Starting SSH Socks proxy to port $SOCKSPort.........Done"
    echo -ne "\n"
}

function SSHPortFwd {   
   # Start SSH Socks proxy
   echo -ne "Starting SSH Port Forwarding to $localPort:$remoteHost:$remotePort.........\r"
   ssh -f -N -p 2200 -i temp -o "IdentitiesOnly=yes" -L $localPort:$remoteHost:$remotePort ec2-user@localhost
    if [[ $? != 0 ]]; then
        echo -ne "Starting SSH Port Forwarding to $localPort:$remoteHost:$remotePort.........Error"
        echo -ne "\n"
        exit
    fi
    echo -ne "Starting SSH Port Forwarding to $localPort:$remoteHost:$remotePort.........Done"
    echo -ne "\n"
}

function generate_random_port {
    localPort=$(( RANDOM % 100 + 56000 ))
    netstat -a -n | grep "127.0.0.1:$localPort" > /dev/null
    if [ $? -eq 1 ]; then
        echo $localPort
    else
        #echo "Port $localPort is not available, trying another port..."
        sleep 1
        generate_random_port
    fi
}

isValidIPv4() {
    local ip="$1"
    local IFS='.' # Internal Field Separator set to dot
    local -a octets=($ip) # Split the IP into an array using IFS

    # Check if there are exactly 4 octets
    [ "${#octets[@]}" -ne 4 ] && return 1

    # Check each octet
    for octet in "${octets[@]}"; do
        # Check if octet is a number and between 0 and 255
        [[ ! $octet =~ ^[0-9]+$ ]] && return 1
        [[ $octet -lt 0 || $octet -gt 255 ]] && return 1
    done

    return 0
}

get_private_ips_from_name() {
    local name_substring="$1"
    local ips=()
    local rds_endpoints=()

    # Use AWS CLI to get the private IP addresses of EC2 instances whose name contains the given substring
    ips=($(aws ec2 describe-instances --filters "Name=tag:Name,Values=*${name_substring}*" --query "Reservations[*].Instances[*].PrivateIpAddress" --output text))

    # Use AWS CLI to get the endpoints of RDS instances whose name contains the given substring
    rds_endpoints=($(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '${name_substring}')].Endpoint.Address" --output text))

    # Combine the two arrays
    combined_ips=("${ips[@]}" "${rds_endpoints[@]}")

    echo "${combined_ips[@]}"
}

get_instance_id_from_private_ip() {
    local private_ip="$1"

    # Use AWS CLI to get the instance ID of the instance with the given private IP address
    instance_id=$(aws ec2 describe-instances --filters "Name=private-ip-address,Values=$private_ip" --query "Reservations[*].Instances[*].InstanceId" --output text)

    # Check if an instance ID was found
    if [ -z "$instance_id" ]; then
        echo "No instance found with private IP address $private_ip."
        exit 1
    else
        echo "$instance_id"
    fi
}

function AppBanner {
    clear
    echo '#############################################'
    echo '#  AWS SSM Session Manager Multi Forwarder  #'
    echo '#############################################'
}

################
###  MAIN   ####
################

clear
echo '#############################################'
echo '#  AWS SSM Session Manager Multi Forwarder  #'
echo '#############################################'

options=("SSM Port FWD" "SSH Port FWD" "SSH Socks PXY" "Display Vars" "Set Port FWD Vars" "Set Socks PXY Vars" "Set AWS Region" "List SSH Tunnels" "Connect to Windows via SSM" "Connect to Windows via SSH Port Foward" "Quit")
while true; do 
    echo ""
    select opt in "${options[@]}"  
    do
        case $opt in
            "SSM Port FWD")
                AppBanner
                echo "you chose 1"
                checkDependencies
                setInstanceIdandAz
                if pgrep session-m &> /dev/null; then echo "SSM Session Manager already running"; else SSMPortForward $remotePort $localPort ; fi
                break;;
            "SSH Port FWD")
                AppBanner
                echo "you chose 2"
                checkDependencies
                setInstanceIdandAz
                loadSSHKey
                if pgrep session-m &> /dev/null; then echo "SSM Session Manager already running"; else SSMPortForward 22 2200 ; fi
                sleep 5
            PXYPORT=$(lsof -nPi |grep LISTEN|egrep "127\.0\.0\.1:$localPort "|cut -f2 -d":"|cut -f1 -d" ")
                if [[ $PXYPORT == $localPort ]]; then echo -e "Port $localPort in use, Port FWD might already be running\nTry setting a different port in the menu";else SSHPortFwd;fi
                break;;
            "SSH Socks PXY")
                AppBanner
                echo "you chose 3"
                checkDependencies
                setInstanceIdandAz
                loadSSHKey
                if pgrep session-m &> /dev/null; then echo "SSM Session Manager already running"; else  SSMPortForward 22 2200 ; fi
                sleep 5
            PXYPORT=$(lsof -nPi |grep LISTEN|egrep "127\.0\.0\.1:$SOCKSPort "|cut -f2 -d":"|cut -f1 -d" ")
                if [[ $PXYPORT == $SOCKSPort ]]; then echo "Port $SOCKSPort in use, SOCKS PXY might already be running";else SSHSockProxy;fi
                break;;
            "Display Vars")
                AppBanner
                echo "you chose 4"
                echo "##### Socks Proxy Vars ######"
                echo SOCKSPort $SOCKSPort
                echo "##### Port FWD Vars ######"
                echo localPort $localPort
                echo remoteHost $remoteHost
                echo remotePort $remotePort
                echo "##### Other Vars ######"
                echo AWS_DEFAULT_REGION $AWS_DEFAULT_REGION
                echo KEYPAIR $KEYPAIR
                break;;
            "Set Port FWD Vars")
                AppBanner
                echo "you chose 5"
                originalPort=$(generate_random_port)
                read -p "localPort  [$originalPort]:" localPort
                localPort=${localPort:-$originalPort}
                echo "localPort  :$localPort"   
                read -p "remotePort  [5432]:" remotePort
                remotePort=${remotePort:-5432}
                echo "remotePort  :$remotePort"              
                read -p "remoteHost  [IP address or host name]:" remoteHost
                remoteHost=${remoteHost:-"10.5.0.6"}
                if isValidIPv4 "$remoteHost"; then
                    echo $remoteHost
                    break
                else
                    ip_addresses=($(get_private_ips_from_name "$remoteHost"))
                    echo "IP Addresses: ${ip_addresses[@]}"
                fi
                if [ "${#ip_addresses[@]}" -eq 1 ] ; then
                    remoteHost="${ip_addresses[0]}"
                    echo $remoteHost
                    break
                elif [ "${#ip_addresses[@]}" -eq 0 ] ; then
                    echo "Invalid input."
                    break
                elif [ "${#ip_addresses[@]}" -gt 1 ] ; then
                        PS3="Select an IP address: "
                        select ip in "${ip_addresses[@]}"; do
                            case $ip in
                                "Quit")
                                    echo "Exiting."
                                    exit
                                    ;;
                                *)
                                    if [[ " ${ip_addresses[@]} " =~ " ${ip} " ]]; then
                                        remoteHost="$ip"
                                        echo "You selected $remoteHost."
                                        break
                                    else
                                        echo "Invalid selection."
                                    fi
                                    ;;
                            esac
                        done    
                fi
      
                break;;
            "Set Socks PXY Vars")
                AppBanner
                echo "you chose 6"
                read -p "SOCKSPort [1080]:" SOCKSPort
                SOCKSPort=${SOCKSPort:-1080}
                echo $SOCKSPort
                break;;
            "Set AWS Region")
                AppBanner
                echo "you chose 7"
                read -p "AWS_DEFAULT_REGION [cn-north-1]:" AWS_DEFAULT_REGION
                AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-cn-north-1}
                echo $AWS_DEFAULT_REGION
                if [[ $AWS_DEFAULT_REGION == "cn-north-1" ]] || [[ $AWS_DEFAULT_REGION == "cn-northwest-1" ]]; then
                    read -p "Full path of Keypair file for Baston:" KEYPAIR
                    echo $KEYPAIR
                fi
                break;;
            "List SSH Tunnels")
                ps aux|grep "ssh -f"|grep temp|cut -f3- -d":"
                ;;
            "Connect to Windows via SSM")
                AppBanner
                echo "you chose 9"
                instance_id=$(get_instance_id_from_private_ip "$remoteHost")
                aws ssm start-session --target $instance_id \
                    --document-name AWS-StartPortForwardingSession \
                    --parameters portNumber="3389",localPortNumber="$localPort" \
                    $AWS_DEFAULT_REGION &
                # Define the path to the .rdp file
                rdpFilePath="/tmp/connection.rdp"
                # Write the configuration to the .rdp file
                echo "full address:s:localhost:$localPort" > $rdpFilePath
                # Open the .rdp file with Microsoft Remote Desktop
                open -a "Microsoft Remote Desktop" $rdpFilePath &
                break;;
            "Connect to Windows via SSH Port Foward")
                AppBanner
                echo "you chose 10"
                # Define the path to the .rdp file
                rdpFilePath="/tmp/connection.rdp"
                # Write the configuration to the .rdp file
                echo "full address:s:localhost:$localPort" > $rdpFilePath
                # Open the .rdp file with Microsoft Remote Desktop
                open -a "Microsoft Remote Desktop" $rdpFilePath &
                break;;
            "Quit")
                echo "Exiting..."
                rm $rdpFilePath
                if pgrep session-m &> /dev/null; then kill $(pgrep session-m); else echo 'SSM process has exited' ; fi
                break
                ;;
            *) echo "invalid option $REPLY";;
        esac
    done
done
