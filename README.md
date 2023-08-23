# ssm
ssm client side tools running on MacOS

The Bastion server must be labeled with a tag named "ServerRole" and its value should be "JumpServers".

If the Bastion server is operating within the AWS China region, you must have a keypair file ready if you intend to use SSH for port forwarding.

Steps to set up:

1. Define the AWS Region.
2. Before utilizing the "SSH Port FWD" feature, execute the "Set Port FWD Vars" 
3. Prior to using the "SSH Socks PXY" function, initiate the "Set Socks PXY Vars"
4. You need to set remote host via "Set Port FWD Vars"  before using ssm related function.


The script will find an avaialble local port automatically. 
If you input a name (or a sub-string of a host name) for a remote host that matches more than 1 servers, you need to select which IP you intend to use.
You need to install Microsoft Remote Desktop before connecting with a Windows server.
