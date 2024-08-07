# aws-access
## A simple shell script to allow SSM Manager EC2 instance to work similar to SSH

```
aws-access <options>
  help                  Help options to the script
  -c [connector]        <required |     always      >      Type of connection [ connect (SSH) | download (SCP) | upload (SCP) ]
  -p [profile]          <required |     always      >      AWS profile used [Get from ~/.aws/config]
  -u [user]             <optional |       all       >      SSH User [Default to ec2-user]
  -l [path]             <required | download/upload >      The file location that should be download/upload 
  -s [ssh public key]   <optional |       all       >      Use to overide the default public key [\$HOME/.ssh/id_rsa.pub]
  -t [ssh private key]  <optional |       all       >      Use to overide the default private key [\$HOME/.ssh/id_rsa]
  -d [directory]        <optional | download/upload >      Use when you want to upload/download a directory [Only accepts \"dir\" as the value]
  -o [directory]        <optional | download/upload >      Use to overide the default file save location for download/upload [~/]
```

### Things to note:
- Make sure you have awscli setup: https://aws.amazon.com/cli/
- Make sure you have session manager plugin setup: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
- Ensure that you setup AWS Profile setup: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html
    For example:
    ```
    [profile tester]
    sso_session = test
    sso_account_id = <aws account id>
    sso_role_name = <aws role>
    region = <aws region>
    output = json
    [sso-session test]
    sso_start_url = <aws sso url>
    sso_region = <aws region>
    sso_registration_scopes = sso:account:access
    ```
- Ensure that the aws role/user have the appropriate access: (More permission require to be added) 
    - Assign ReadOnly Access to S3 and EC2
    ```json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeInstances",
                    "ssmmessages:CreateControlChannel",
                    "ssmmessages:CreateDataChannel",
                    "ssmmessages:OpenControlChannel",
                    "ssmmessages:OpenDataChannel",
                    "ssm:CreateDocument",
                    "ssm:DescribeInstanceProperties",
                    "ssm:DescribeInstanceInformation"
                    "ssm:DescribeSessions",
                    "ssm:GetConnectionStatus",
                    "ssm:GetDocument",
                    "ssm:ListCommands",
                    "ssm:ListCommandInvocations",
                    "ssm:ResumeSession",
                    "ssm:TerminateSession",
                    "ssm:SendCommand",
                    "ssm:StartSession",
                    "ssm:UpdateDocument",
                    "ssm:UpdateInstanceInformation"
                ],
                "Resource": "*"
            }
        ]
    }
    ```
- Generate your own public and private key, as it default to read from `$HOME/.ssh/id_rsa.pub` and `$HOME/.ssh/id_rsa`
    ```
    ssh-keygen -t rsa -b 4096
    ```