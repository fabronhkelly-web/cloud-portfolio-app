# TEST ONLY: proves the pipeline blocks insecure code.
# Delete this file right after the test.
resource "aws_security_group" "checkov_block_test" {
  name        = "checkov-block-test"
  description = "Test only - should be blocked by Checkov"

  ingress {
    description = "SSH from anywhere (insecure on purpose)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
