provider "aws" {
  region = "us-east-1"
}

variable "server_port" {
  description = "Port to connect server instance"
  default = 8080
  type = number
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group" "sg-ec2" {
  description = "Allow traffic to EC2 instance"
  name = "tf-ec2-sg"

  ingress {
    from_port = var.server_port
    protocol = "TCP"
    to_port = var.server_port
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "ec2_lc" {
  image_id = "ami-0bcc094591f354be2"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.sg-ec2.id]

  user_data = <<-EOF
                  #!/bin/bash
                  echo "Hello world..!" > index.html
                  nohup busybox httpd -f -p ${var.server_port} &
                EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ec2-asg" {
  launch_configuration = aws_launch_configuration.ec2_lc.name
  target_group_arns = [aws_lb_target_group.alb-tg.arn]
  vpc_zone_identifier = data.aws_subnet_ids.default.ids

  health_check_type = "ELB"
  max_size = 4
  min_size = 2
  tag {
    key = "Name"
    propagate_at_launch = true
    value = "tf-asg-ec2"
  }
}

resource "aws_lb" "ec2-lb" {
  name = "terraform-ec2-alb"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.alb-sg.id]
}

resource "aws_lb_listener" "ec2-lb-lis" {
  load_balancer_arn = aws_lb.ec2-lb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "tf-alb-lis-rule" {
  listener_arn = aws_lb_listener.ec2-lb-lis.arn
  priority = 100
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_lb_target_group" "alb-tg" {
  name = "terraform-alb-tg"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 3
    unhealthy_threshold = 3
  }
}

resource "aws_security_group" "alb-sg" {
  name = "tf-alb-sg"

  # Allow inbound traffic HTTP requests
  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Allow all outbound connections
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "ec2_public_ip" {
  value = aws_lb.ec2-lb.dns_name
  description = "Load Balance DNS name"
}

