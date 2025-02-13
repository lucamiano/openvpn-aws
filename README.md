# openvpn-aws
## Introduction
The aim of this project is to automatize the process of creating a OpenVPN server on a AWS.
The provided script is capable of providing the functionalities of a VPN, deploying the server and generating a profile to be imported in OpenVPN client
## Getting started
### AWS
**Clone the repository**:
https://github.com/lucamiano/openvpn-aws.git

**Launch the script**:

```bash
./launch-ec2-vpn.sh "AWS-REGION"
```
**Import the generated profile to OpenVPN**:
https://openvpn.net/connect-docs/import-profile.html

**[Optional]: Cleanup resources:**
```bash
./cleanup.sh "AWS-REGION"
```

