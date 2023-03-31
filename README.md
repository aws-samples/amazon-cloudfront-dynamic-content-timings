# cloudfront-dynamic-content-timings


This sample project provides a python script for CloudFront timings measurement. 
The script uses [Pycurl](http://pycurl.io/) module and utilizes Curl [write-out](https://everything.curl.dev/usingcurl/verbose/writeout) capabilities. 

**Note**
If you don't want to install Pycurl on your local machine, see below how you can run the script using AWS CloudShell

The following metrics are captured by curl and printed out:
- TOTAL_TIME: the total time in seconds for the previous transfer, including name resolving, TCP connect etc. 
- NAMELOOKUP_TIME: the total time in seconds from the start until the name resolving was completed.
- CONNECT_TIME: the total time in seconds from the start until the connection to the remote host (or proxy) was completed.
- APPCONNECT_TIME:  the time, in seconds, it took from the start until the SSL/SSH connect/handshake to the remote host was completed
- STARTTRANSFER_TIME: the time, in seconds, it took from the start until the first byte is received by libcurl (**User First Byte Latency**)
- SPEED_DOWNLOAD: the download speed in bytes/second

Additionally, [CloudFront Server-Timing header](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-response-headers-policies.html#server-timing-header) is used to capture the following metrics in response from CloudFront:
- cdn-upstream-connect: the time in milliseconds between when the origin DNS request completed and a TCP (and TLS, if applicable) connection to the origin completed. A value of zero (0) indicates that CloudFront reused an existing connection
- cdn-upstream-fbl: the time in milliseconds between when the origin HTTP request is completed and when the first byte is received in the response from the origin (**Origin First Byte Latency**)
- cdn-downstream-fbl: the time in milliseconds  between when the edge location finished receiving the request and when it sent the first byte of the response to the viewer (**CloudFront First Byte Latency**)

These metrics enable us to analyse performance bottlenecks in the round trip request processing flow between user and Origin.
Also, we can see the impact of upstream connection reuse by CloudFront on the total download time.

The script can be used standalone against any CloudFront distribution with the Server-Timing header enabled. 

However, to make testing easier the test system is provided as part of this sample.
The test system comprises of CloudFront distribution and Amazon EC2 with Nginx server running behind Application Load Balancer. 
CloudFront distribution uses a managed cache policy [CachingDisabled](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html#managed-cache-policy-caching-disabled) which is useful for dynamic content. 
It also includes some security best practices, specifically, ALB and EC2 Security Group allows only requests coming from the CloudFront distribution, disabling any requests coming directly from the Internet.

![Solution Diagram](/pics/arch.png)


The system is provisioned using Terraform.
Frst make sure you use the right AWS account - for example, you might use a dev account:
`export AWS_PROFILE=myDevAccount`

You may also change instance configuration and the region where resources are provisioned to by changing *aws_region* in variable.tf file (default is eu-west-1).

Run the following commands:
```
terraform init
terraform apply
```

Once the installation is completed, the CloudFront distribution URL will be printed out. 
Use it to run the script:

`timings.py -url https://d3w4bt3xbw4rhc.cloudfront.net -n 100`

Example output:

```
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|   Request number |   Download time |   DNS resolution |   Downstream connect time |   Downstream TCP+SSL time |   Upstream TCP+SSLt time |   User FBL |   CF FBL |   Origin FBL |   Download speed, Mbps |
+==================+=================+==================+===========================+===========================+==========================+============+==========+==============+========================+
|                1 |           220.8 |             64.6 |                      69.5 |                     103.6 |                       39 |      104.3 |      106 |           85 |                    0.1 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                2 |           124   |              0   |                       5.9 |                      27.3 |                       40 |       27.5 |       87 |           86 |                    0.2 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                3 |            91.6 |              0   |                       4.9 |                      26.2 |                        0 |       26.5 |       55 |           43 |                    0.3 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                4 |           138.1 |              0   |                       5.6 |                      26.1 |                       40 |       26.3 |      102 |           89 |                    0.2 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                5 |           130.5 |              0   |                       5.4 |                      24.7 |                       39 |       24.9 |       94 |           84 |                    0.2 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                6 |           120.4 |              0.1 |                       6.6 |                      26.1 |                       39 |       26.3 |       86 |           84 |                    0.2 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                7 |            82.4 |              0.1 |                       6.5 |                      27   |                        0 |       27.2 |       46 |           44 |                    0.3 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                8 |            83.8 |              0   |                       5.1 |                      26.3 |                        0 |       26.5 |       49 |           47 |                    0.3 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|                9 |            89.4 |              0   |                       5.5 |                      26.7 |                        0 |       26.9 |       55 |           46 |                    0.3 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
|               10 |           110   |              0   |                       4.6 |                      18.4 |                       39 |       18.5 |       85 |           83 |                    0.2 |
+------------------+-----------------+------------------+---------------------------+---------------------------+--------------------------+------------+----------+--------------+------------------------+
Total downstream connections: 10
Number of re-used upstream connections: 4
Average download time for re-used upstream connections: 87 ms
Average download time for new upstream connections: 141 ms
Latency gain: 38.3 %
```

Try experimenting with the number of requests using *-n* argument. Note that the more requests you send, the more effective upstream connection reuse, resulting in lower total latency. 
You may also check if you can connect to ALB or EC2 directly - these requests should be blocked as we only allow requests from the CloudFront distribution.

### Run script in CloudShell

To run the script from the Cloud perform the following steps:

- Go to [CloudShell console](https://console.aws.amazon.com/cloudshell/home)
- Install the following modules:
```
sudo yum install python3-pycurl.x86_64
pip3 install tabulate
```
- Select Actions -> Upload file and upload timings.py script
- Run script
```
python3 timings.py -url https://d3w4bt3xbw4rhc.cloudfront.net -n 10
```

