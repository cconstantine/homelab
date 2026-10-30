# The ServiceAccount a deploy job uses to run
# `terraform apply -target=module.smelt`. See smelt-deployer/main.tf.
module "smelt_deployer" {
  source = "./smelt-deployer"
}
