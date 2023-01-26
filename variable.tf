
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "ami_id" {
  description = "ami id"
  type        = string
  default     = "ami-05e786af422f8082a" #Canonical, Ubuntu, 22.04 LTS, amd64 jammy image build on 2022-12-01
}

variable "instance_type" {
  description = "EC2 Instance type"
  type        = string
  default     = "t2.micro" #Free tier eligible
}

variable "ec2_count" {
  description = "Number of EC2 Instances"
  type        =  number
  default     = 1
}


