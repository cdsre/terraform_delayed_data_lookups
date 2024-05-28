module "some_other_module" {
  source = "./modules/myother"
}

module "buckets" {
  source     = "./modules/mybucket"
  depends_on = [module.some_other_module]
}