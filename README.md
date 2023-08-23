# ssm
ssm client side tools

1. Bastion server need to have a tag -  ServerRole:JumpServers
2. If the bastion is running in AWS China region, you need to prepare a keypair file if you use ssh port forward
3. setup steps: 
   1. Set AWS Region
   2. Before using "SSH Port FWD" you need to run "Set Port FWD Vars"
   3. Before using "SSH Socks PXY" you need to run "Set Socks PXY Vars"
