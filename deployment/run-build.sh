#!/usr/bin/env bash

set -e

export REGION=eu-west-1 # the AWS region to launch the solution (e.g. us-east-1)
export BUCKET_PREFIX=rms-aws-distributed-load-testing-bucket # prefix of the bucket name without the region code
export BUCKET_NAME=$BUCKET_PREFIX-$REGION # full bucket name where the code will reside
export SOLUTION_NAME=distributed-load-testing-on-aws
export VERSION=v1.0.0 # version number for the customized code
export PUBLIC_ECR_REGISTRY=public.ecr.aws/aws-solutions # replace with the container registry and image if you want to use a different container image
export PUBLIC_ECR_TAG=v3.2.5 # replace with the container image tag if you want to use a different container image

#./build-s3-dist.sh $BUCKET_PREFIX $SOLUTION_NAME $VERSION

echo "Checking to see if the $BUCKET_NAME bucket exists..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Found bucket"
else
    echo "Could not find bucket, creating the initial bucket using the stack..."

    aws cloudformation create-stack \
        --stack-name rms-aws-distributed-load-testing-s3-deploy-stack \
        --template-body "file://s3-deploy-stack.json" \
        --capabilities CAPABILITY_IAM \
        --role-arn arn:aws:iam::253011676286:role/rms-codepipeline-cloudformation-role \
        --on-failure DELETE

    echo "Waiting until bucket is created..."

    NEXT_WAIT_TIME=0
    until (( NEXT_WAIT_TIME == 10 )); do

        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            NEXT_WAIT_TIME = 10
        else
            echo "Could not find bucket, sleeping for 30s"
            NEXT_WAIT_TIME=$((NEXT_WAIT_TIME + 1))
            sleep 30
        fi
        
    done
    (( NEXT_WAIT_TIME < 10 ))

    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "Bucket created successfully"
    else
        echo "Could not find bucket, check the stack, exiting..."
        exit 1
    fi

fi

echo "Uploading the produced template to S3..."

aws s3 sync global-s3-assets s3://$BUCKET_NAME/$SOLUTION_NAME/$VERSION
aws s3 sync regional-s3-assets s3://$BUCKET_NAME/$SOLUTION_NAME/$VERSION

# template url is s3://rms-aws-distributed-load-testing-bucket-eu-west-1/rms-aws-distributed-load-testing/v1.0.0/distributed-load-testing-on-aws.template
# s3://$BUCKET_NAME/$SOLUTION_NAME/$VERSION/$SOLUTION_NAME.template

echo "Creating or updating stack based off of generated template..."
echo "Using template url: https://$BUCKET_NAME.s3.eu-west-1.amazonaws.com/$BUCKET_NAME/$SOLUTION_NAME/$VERSION/$SOLUTION_NAME.template"

if aws cloudformation describe-stacks --stack-name rms-aws-distributed-load-testing-stack &>/dev/null 
then
    aws cloudformation update-stack \
        --stack-name rms-aws-distributed-load-testing-stack \
        --template-url "https://$BUCKET_NAME.s3.eu-west-1.amazonaws.com/$SOLUTION_NAME/$VERSION/$SOLUTION_NAME.template" \
        --parameters "file://distributed-load-testing-params.json" \
        --capabilities CAPABILITY_IAM \
        --role-arn arn:aws:iam::253011676286:role/rms-codepipeline-cloudformation-role
else
    aws cloudformation create-stack \
        --stack-name rms-aws-distributed-load-testing-stack \
        --template-url "https://$BUCKET_NAME.s3.eu-west-1.amazonaws.com/$SOLUTION_NAME/$VERSION/$SOLUTION_NAME.template" \
        --parameters "file://distributed-load-testing-params.json" \
        --capabilities CAPABILITY_IAM \
        --role-arn arn:aws:iam::253011676286:role/rms-codepipeline-cloudformation-role \
        --on-failure DELETE
fi
