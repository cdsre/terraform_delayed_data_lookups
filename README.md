# terraform_delayed_data_lookups

## Overview
A few weeks ago a college asked me to look at some terraform behaviour they were not expecting. They had a module that
would create an S3 bucket and used data lookups to get the account ID and region to form a unique bucket name. They had
a root module that called off to other modules and used the `depends_on` meta-argument to ensure that one module ran
before the other.

However, they were seeing that when they made a change to the first module, the second module was trying to recreate the
bucket. This was unexpected as the bucket configuration had not changed. And its name was based on data lookups that
would be known at the plan time.

It can be quite common to use data lookup’s in terraform to get information or attributes about resources that are not 
under your configurations control. In the terraform AWS provider a common data look up is to get the account ID or aws 
region. These can then be used in things like IAM policy documents to restrict access or control. Or sometimes in 
resources like S3 buckets to ensure your bucket is a unique name. 

## Data lookups in isolation
Generally speaking data lookups will happen in the plan phase. This is when terraform is evaluating the configuration
and can be used to get information that will act as input to other resources.

```hcl
data "aws_caller_identity" "this" {}
data "aws_region" "this" {}
resource "aws_s3_bucket" "couchbase_backup" {
  bucket        = "my-unique-bucket-${data.aws_caller_identity.this.account_id}-${data.aws_region.this.id}"
}
```

When we run this configuration it creates us a new bucket using the account Id and region as part of the bucket name.

```bash
Plan: 1 to add, 0 to change, 0 to destroy.
aws_s3_bucket.couchbase_backup: Creating...
aws_s3_bucket.couchbase_backup: Creation complete after 1s [id=test-123456789123-eu-west-2-my-bucket]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

If we run this again we will see that the bucket is already created and terraform will not try to create it again.

```bash
No changes. Your infrastructure matches the configuration.
Terraform has compared your real infrastructure against your configuration and found no differences, so no changes are needed.
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

## Data lookups in modules
As good DevOps engineers we decide hey this code is useful in lots of places lets move it out to a module. We publish 
this and tell others to feel free to consume it. Another engineer starts using it but for what ever reason they need to 
ensure some other module runs before this one. The module being run before ours is irrelevant. For this example we will 
use a time_sleep resource. 

So they build their terraform code like this:

```hcl
module "some_other_module" {
  source = "./modules/myother"
}

module "buckets" {
  source = "./modules/mybucket"
  depends_on = [module.some_other_module]
}
```

This ensures that the bucket module will not run until after the other module has complete. Running this the first time,
it works as expected and our resources are created: `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`. 
However, when run a second time we see that Terraform is happy `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`.

We then make a change to the `some_other_module` and run terraform again. This time we see that the Terraform wants to
destroy and recreate our bucket, Even though our bucket object configuration has not changed. 

```bash
  # module.buckets.aws_s3_bucket.couchbase_backup must be replaced
-/+ resource "aws_s3_bucket" "couchbase_backup" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      ~ arn                         = "arn:aws:s3:::test-123456789123-eu-west-2-my-bucket" -> (known after apply)
      ~ bucket                      = "test-123456789123-eu-west-2-my-bucket" # forces replacement -> (known after apply) # forces replacement
      ~ bucket_domain_name          = "test-123456789123-eu-west-2-my-bucket.s3.amazonaws.com" -> (known after apply)
      + bucket_prefix               = (known after apply)
```

So....what gives? The bucket is relying only on data lookups and these can be run in the plan phase. So why is it trying
to recreate the bucket? Why does it say the name won't be known until after the apply?

The reason is that we have used a dependency meta-argument in our module. This tells terraform that the module has a
dependency on another module. This is a good thing as it ensures that the module will not run until after the other module.
This includes its data lookups. Since the data lookup cannot be run in the module until after the previous modules 
changes are applied Terraform cannot know that the bucket config is the same at the plan phase.

## Conclusion
The above is an example of a scenario that caught me out in actual module code i wrote in the past. I had always thought
that data lookups were run in the plan phase and that they would not be affected by the order of modules. However, this
is documented by Hashicorp in the 
[depends_on meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on#processing-and-planning-consequences)
and in the [data Sources Block](https://developer.hashicorp.com/terraform/language/data-sources#data-resource-behavior). 
Lookups can be delayed for a number of reasons and not be able to be run until the apply phase.

In summary, we don't know how people might use the modules we create. While we might build and test our modules in 
isolation, and run all sorts of testing with tools like terratest, we cannot predict how others will use our modules. We 
should try to avoid using data lookups in modules directly and instead leave that responsibility to the consumer of the 
module. Our module will be cleaner if we just asked the caller to pass us the region and account id, or even in this 
case the bucket name. That way the caller can obtain that data from any source and our module will not be specifically 
tied to data lookups.

