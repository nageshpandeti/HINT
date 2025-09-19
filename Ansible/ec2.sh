aws ec2 describe-instance-types \
    --filters "Name=free-tier-eligible,Values=true" \
    --query "InstanceTypes[*].InstanceType"

