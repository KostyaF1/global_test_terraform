data "aws_availability_zones" "available" {}

data "template_file" "init" {
  template = "${file("${var.template_path}init.tpl")}"

  vars {
    conf_file_name = "${var.conf_file_name}"
    remote_conf_file_path_nginx = "${var.remote_conf_file_path_nginx}"
    remote_static_file_path = "${var.remote_static_file_path}"
    remote_tmp_path_nginx = "${var.remote_tmp_path_nginx}"
  }
}

data "aws_subnet_ids" "global_subnets" {
  depends_on = ["aws_subnet.global_subnet"]
  vpc_id = "${aws_vpc.global_vpc.id}"
}

data "aws_ami" "nat_ami" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ami-ubuntu-16.04*"]
  }
}

data "aws_route53_zone" "global_zone"{
  name = "${var.domain_name}"
  private_zone = "false"
}


# Templates
data "template_file" "global_ec2_policy" {
  template = "${file("${var.template_path}global_ec2_policy.json.tpl")}"

  vars {
    ec2_addresses = "${aws_instance.global_instance.*.public_ip[count.index]}"
    s3_resource = "${aws_s3_bucket.global_s3.arn}"
    elb_resource = "${aws_lb.global-lb.arn}"
  }
}

data "template_file" "global_s3_policy" {
  template = "${file("${var.template_path}s3_policy.json.tpl")}"
  vars {
    ec2_addresses = "${element(aws_instance.global_instance.*.private_ip, count.index)}"
    s3_resource = "${aws_s3_bucket.global_s3.arn}"
  }
}

data "template_file" "global_ec2_role" {
  template = "${file("${var.template_path}global_ec2_role.json.tpl")}"

}
/*
data "template_file" "global_nginx_conf" {
  template = "${file("${var.template_path}global_ml.conf.tpl")}"
  vars {
    remote_static_file_path = "${var.remote_static_file_path}"
  }
}*/