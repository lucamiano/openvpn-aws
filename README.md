# openvpn-aws
## Introduction
The aim of this project is to automatize the process of creating a OpenVPN server on a AWS.
The provided script is capable of providing the functionalities of a VPN, deploying the server and generating a profile to be imported in OpenVPN client
## Getting started [AWS]
**Clone the repository**:
https://github.com/lucamiano/openvpn-aws.git

**Prerequisites:**

Install AWS CLI: (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

Generate Access and Secret Key for IAM User: (https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html)

Run aws configure: (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html)

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


### References
https://medium.com/@zhongli_69231/setting-up-an-openvpn-service-on-aws-and-azure-vms-using-docker-compose-f13f7a7edb3c


