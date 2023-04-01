# Fetch all availability zones in the region
data "aws_availability_zones" "azs" {}

#Create VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "CF-dynamic"
  }
}

# Create Public subnets
resource "aws_subnet" "public_subnet" {
  count                   = "${length(data.aws_availability_zones.azs.names)}"
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "192.168.${1+count.index}.0/24"
  availability_zone       = "${data.aws_availability_zones.azs.names[count.index]}"
  map_public_ip_on_launch = true
  tags = {
    Name = "CF-dynamic-public-subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id                = aws_vpc.custom_vpc.id
  tags = {
    Name = "CF-dynamic"
  }
}

# Create Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id                = aws_vpc.custom_vpc.id
}

# Create Public Route
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Create Public Route Table Association
resource "aws_route_table_association" "public_rt_association" {
  count = length(aws_subnet.public_subnet)
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = aws_subnet.public_subnet[count.index].id
}

# Create Security Group
resource "aws_security_group" "front-end-sg" {
  name        = "front-end-sg"
  description = "Allow only HTTP through CloudFront"
  vpc_id      = aws_vpc.custom_vpc.id
  egress = [
    {
      description      = "Allow all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1" #all
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]
}

# Get CloudFront managed prefix list
data "aws_ec2_managed_prefix_list" "cloudfront" {
 name = "com.amazonaws.global.cloudfront.origin-facing"
}
# Add CloudFront prefix list to the security group
resource "aws_security_group_rule" "ingress_cloudfront" {
 description        = "Allow CloudFront IPs"
 security_group_id  = aws_security_group.front-end-sg.id
 type               = "ingress"
 from_port          = 80
 to_port            = 80
 protocol           = "tcp"
 prefix_list_ids    = [data.aws_ec2_managed_prefix_list.cloudfront.id]
}
# Allow traffic within SG
resource "aws_security_group_rule" "ingress_ALB" {
 description        = "Allow inter SG traffic"
 security_group_id  = aws_security_group.front-end-sg.id
 type               = "ingress"
 from_port          = 80
 to_port            = 80
 protocol           = "tcp"
 self               = true
}

# Create EC2 Instance
resource "aws_instance" "nginx" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  subnet_id            = aws_subnet.public_subnet[1].id
  security_groups      = [aws_security_group.front-end-sg.id]
  user_data            = file("userdata.sh")
  tags = {
    "Name" = "CF-dynamic-Nginx"
  }
}

# Create Target Group
resource "aws_lb_target_group" "tg" {
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = aws_vpc.custom_vpc.id
}

# Attach Target Group to Instance
resource "aws_alb_target_group_attachment" "tgattachment" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.nginx.id
}

# Create Application Load balancer
resource "aws_lb" "lb" {
  name               = "CF-dynamic-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.front-end-sg.id]
  subnets            = aws_subnet.public_subnet.*.id
  drop_invalid_header_fields = true
}

# Create Listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied"
      status_code  = "403"
    }
  }
}

#Allow only requests carrying a secret header
resource "aws_lb_listener_rule" "secret_header_validation" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }

  condition {
    http_header {
      values           = ["dIwBjqu6"]
      http_header_name = "X-Secret-Header"
    }
  }
}

# Create Response Headers Policy with timing headers
resource "aws_cloudfront_response_headers_policy" "timing_headers" {
  name = "timing_headers"

  server_timing_headers_config {
    enabled       = true
    sampling_rate = 100
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "distribution" {
  comment = "CF-dynamic"
  origin {
    domain_name = aws_lb.lb.dns_name
    origin_id   = "ALB"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_keepalive_timeout = 60
    }
    custom_header {
      name = "X-Secret-Header"
      value = "dIwBjqu6"
    }
  }

  enabled             = true
  default_root_object = "test.png"

  default_cache_behavior {
    allowed_methods             = ["GET", "HEAD", "OPTIONS"]
    cached_methods              = ["GET", "HEAD"]
    target_origin_id            = "ALB"
    cache_policy_id             = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # CachingDisable
    origin_request_policy_id    = "216adef6-5c7f-47e4-b989-5492eafa07d3"  # AllViewer
    #response_headers_policy_id  = "5cc3b908-e619-4b99-88e5-2cf7f45965bd"  # CORS-With-Preflight
    response_headers_policy_id  = aws_cloudfront_response_headers_policy.timing_headers.id
    viewer_protocol_policy      = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "cloudfront_distribution" {
  value = aws_cloudfront_distribution.distribution.domain_name
}



