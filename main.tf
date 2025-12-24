resource "aws_instance" "india_ec2" {
  ami           = "ami-02b3c48b29faf59db"
  instance_type = "t2.micro"

  tags = {
    Name = "ec2-india"
  }
}

resource "aws_instance" "us_ec2" {
  provider      = aws.us
  ami           = "ami-0d55b018c95fe9bfd"
  instance_type = "t2.micro"

  tags = {
    Name = "ec2-us"
  }
}
