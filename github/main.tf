# The smelt repo was created by hand and imported (see the import blocks in
# ../github.tf). Settings mirror what the repo already had, so the import
# changes nothing; only the branch protection below is new.
resource "github_repository" "smelt" {
  name       = "smelt"
  visibility = "private"

  has_issues   = true
  has_projects = true
  has_wiki     = true

  allow_merge_commit = true
  allow_squash_merge = true
  allow_rebase_merge = true

  lifecycle {
    prevent_destroy = true
  }
}

# No direct pushes to main, admins included (no bypass actors): everything
# lands through a pull request. Zero required approvals because there is one
# human here and GitHub doesn't let you approve your own PR. A ruleset rather
# than github_branch_protection: the latter reads back over GraphQL, which
# needs a read:org scope the homelab PAT doesn't have.
resource "github_repository_ruleset" "smelt_main" {
  name        = "main"
  repository  = github_repository.smelt.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count = 0
    }
  }
}
