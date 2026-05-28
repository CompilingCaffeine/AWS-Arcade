SHELL := /usr/bin/env bash

BOOTSTRAP_DIR := terraform/envs/bootstrap
PROD_DIR := terraform/envs/prod
LAMBDA_DIR := lambdas/package_processor
VENV := .venv

.DEFAULT_GOAL := help

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

$(VENV)/bin/pytest:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --upgrade pip
	$(VENV)/bin/pip install --quiet -r $(LAMBDA_DIR)/requirements-dev.txt

.PHONY: test
test: $(VENV)/bin/pytest  ## Run Lambda unit tests
	$(VENV)/bin/pytest $(LAMBDA_DIR)/tests/

.PHONY: lint
lint: fmt tflint checkov  ## Run terraform fmt, tflint, and checkov

.PHONY: fmt
fmt:  ## terraform fmt -check on the prod env
	terraform -chdir=$(PROD_DIR) fmt -check -recursive

.PHONY: fmt-fix
fmt-fix:  ## terraform fmt (rewrite in place)
	terraform -chdir=$(PROD_DIR) fmt -recursive

.PHONY: tflint
tflint:  ## Run tflint recursively
	tflint --init
	tflint --recursive

.PHONY: checkov
checkov:  ## Run checkov against the terraform tree
	checkov --config-file .checkov.yml

.PHONY: validate
validate:  ## terraform validate on prod env (requires init)
	terraform -chdir=$(PROD_DIR) validate

.PHONY: bootstrap-init
bootstrap-init:  ## Init the bootstrap env (state bucket + lock table)
	terraform -chdir=$(BOOTSTRAP_DIR) init

.PHONY: bootstrap-apply
bootstrap-apply:  ## Apply the bootstrap env
	terraform -chdir=$(BOOTSTRAP_DIR) apply

.PHONY: init
init:  ## Init prod env using backend.hcl
	terraform -chdir=$(PROD_DIR) init -backend-config=backend.hcl

.PHONY: plan
plan:  ## Plan prod env
	terraform -chdir=$(PROD_DIR) plan -var-file=terraform.tfvars

.PHONY: apply
apply:  ## Apply prod env
	terraform -chdir=$(PROD_DIR) apply -var-file=terraform.tfvars

.PHONY: sample-zip
sample-zip:  ## Build the sample game ZIP at /tmp/sample-game.zip
	bash scripts/create-sample-game-zip.sh

.PHONY: sample-upload
sample-upload: sample-zip  ## Upload the sample game ZIP to the live upload bucket
	aws s3 cp /tmp/sample-game.zip \
	  s3://$$(terraform -chdir=$(PROD_DIR) output -raw upload_bucket_name)/incoming/sample-game.zip

.PHONY: clean
clean:  ## Remove local venv and build artifacts
	rm -rf $(VENV) .pytest_cache
	find . -type d -name "__pycache__" -prune -exec rm -rf {} +
