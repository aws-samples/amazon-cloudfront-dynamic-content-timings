#!/bin/bash
sudo apt update -y
sudo apt install -y nginx
cd /var/www/html/
wget http://awsmedia.s3.amazonaws.com/AWS_logo_poweredby_black_127px.png -O test.png
sudo service nginx start

