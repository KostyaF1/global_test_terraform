provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.regions["Europe"]}"
}

resource "aws_vpc" "global_vpc" {
  cidr_block       = "10.192.0.0/16"
  instance_tenancy = "default"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"

  tags = {
    Name = "${var.tag_name}-vpc"
  }
}

resource "aws_internet_gateway" "global_internet_gateway" {
  vpc_id = "${aws_vpc.global_vpc.id}"

  tags = {
    Name = "${var.tag_name}-ig"
  }
}

resource "aws_subnet" "global_subnet" {
  count = 2
  cidr_block = "${element(var.cidr, count.index)}"
  vpc_id = "${aws_vpc.global_vpc.id}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "${var.tag_name}-subnet"
  }
}

resource "aws_route_table" "global_route_table" {
  count = 2
  vpc_id = "${aws_vpc.global_vpc.id}"
  tags = {
    Name = "${var.tag_name}-rt"
  }
}

resource "aws_route" "global_route" {
  count = 2
  route_table_id = "${element(aws_route_table.global_route_table.*.id, count.index)}"
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.global_internet_gateway.id}"
}

resource "aws_route_table_association" "global_rta" {
  count = 2
  subnet_id      = "${element(data.aws_subnet_ids.global_subnets.ids, count.index)}"
  route_table_id = "${element(aws_route_table.global_route_table.*.id, count.index)}"
}

resource "aws_instance" "global_instance" {
  count = 2
  ami           = "${data.aws_ami.nat_ami.id}"
  instance_type = "${var.instance_type}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"
  subnet_id = "${element(aws_subnet.global_subnet.*.id, count.index)}"
  security_groups = ["${aws_security_group.global_sg.id}"]
  key_name = "${var.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.global_ec2_profile.name}"
  user_data = "${data.template_file.init.rendered}"
  tags = {
    Name = "${var.tag_name}-ec2"
  }
}

resource "aws_iam_policy" "global_ec2_policy" {
  name = "${var.tag_name}-EC2Policy"
  policy = "${data.template_file.global_ec2_policy.rendered}"
}

resource "aws_iam_role" "global_ec2_role" {
  name = "${var.tag_name}-EC2Role"
  path = "/"
  assume_role_policy = "${data.template_file.global_ec2_role.rendered}"
}

resource "aws_iam_role_policy_attachment" "global_policy_att" {
  policy_arn = "${aws_iam_policy.global_ec2_policy.arn}"
  role = "${aws_iam_role.global_ec2_role.name}"
}

resource "aws_iam_instance_profile" "global_ec2_profile" {
  name = "${var.tag_name}EC2Profile"
  role = "${aws_iam_role.global_ec2_role.name}"
}

resource "aws_security_group" "global_sg" {
  name        = "${var.tag_name}-sg"
  description = "EC2 Security Group"
  vpc_id = "${aws_vpc.global_vpc.id}"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.tag_name}-sg"
  }
}

resource "aws_lb" "global-lb" {
  name               = "${var.tag_name}-lb"
  load_balancer_type = "application"

  subnets = ["${data.aws_subnet_ids.global_subnets.ids}"]
  security_groups = ["${aws_security_group.global_lb_sg.id}"]

  tags = {
    Name = "${var.tag_name}-elb"
  }
}

resource "aws_lb_listener" "global_lb_listener" {
  load_balancer_arn = "${aws_lb.global-lb.arn}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn = "${aws_acm_certificate.cert.arn}"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.global_lb_target_group.arn}"
  }
}

resource "aws_lb_target_group" "global_lb_target_group" {
  name     = "${var.tag_name}-lb-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.global_vpc.id}"
}

resource "aws_lb_target_group_attachment" "global_lb_target_group_attachment" {
  count = 2
  target_group_arn = "${aws_lb_target_group.global_lb_target_group.arn}"
  target_id        = "${element(aws_instance.global_instance.*.id, count.index)}"
  port             = 8080
}

resource "aws_security_group" "global_lb_sg" {
  name        = "${var.tag_name}-lbsg"
  description = "ELB Security Group"
  vpc_id = "${aws_vpc.global_vpc.id}"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.tag_name}-elbsg"
  }
}

resource "aws_s3_bucket" "global_s3" {
  bucket = "s3-website-${var.domain_name}"
  acl    = "private"

  tags = {
    Name = "${var.tag_name}-s3"
  }
}

resource "aws_s3_bucket_policy" "global_s3_policy" {
  bucket = "${aws_s3_bucket.global_s3.id}"
  policy = "${data.template_file.global_s3_policy.rendered}"
}

resource "aws_s3_bucket_object" "html_object" {
  bucket = "${aws_s3_bucket.global_s3.bucket}"
  key    = "${var.static_file_name}"
  source = "${var.file_path}${var.static_file_name}"
  etag   = "${md5(file("/${var.file_path}${var.static_file_name}"))}"
}

resource "null_resource" "global_cluster" {
  count = 2
  connection {
    host = "${element(aws_instance.global_instance.*.public_ip, count.index)}"
    user = "ubuntu"
    private_key = "${file("${var.key_path}${var.key_name}")}"

  }

  provisioner "file" {
    destination = "${ var.remote_tmp_path_nginx }${var.conf_file_name}"
    source = "${var.conf_file_path}${var.conf_file_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm ${ var.remote_conf_file_path_nginx }default",
      "sudo mv ${ var.remote_tmp_path_nginx }${var.conf_file_name} ${ var.remote_conf_file_path_nginx }${var.conf_file_name}",
      "sudo systemctl restart nginx",
      "sleep 10",
      "sudo aws s3 cp s3://${aws_s3_bucket.global_s3.bucket}/${var.static_file_name} ${var.remote_static_file_path}${var.static_file_name}"
    ]
  }
  depends_on = ["aws_iam_role_policy_attachment.global_policy_att"]
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.tag_name}-lb-dns"
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.rout53_validation.fqdn}"]
}

resource "aws_route53_record" "rout53_validation" {
  name    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.global_zone.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_route53_record" "dev-ns" {
zone_id = "${data.aws_route53_zone.global_zone.zone_id}"
name    = "${var.domain_name}"
type    = "A"
alias {
evaluate_target_health = false
name = "${aws_lb.global-lb.dns_name}"
zone_id = "${aws_lb.global-lb.zone_id}"
}
}
