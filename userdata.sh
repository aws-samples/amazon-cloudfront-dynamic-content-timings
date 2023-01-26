#!/bin/bash
sudo apt update -y
sudo apt install -y nginx
#sudo echo "<p>This is a test page</p>" >/var/www/html/index.html
#sudo echo "<a href="http://aws.amazon.com/what-is-cloud-computing"><img src="http://awsmedia.s3.amazonaws.com/AWS_logo_poweredby_black_127px.png" alt="Powered by AWS Cloud Computing"></a>" > /var/www/html/index.html
cd /var/www/html/
wget http://awsmedia.s3.amazonaws.com/AWS_logo_poweredby_black_127px.png -O aws_logo.png
sudo service nginx start

