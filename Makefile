.DEFAULT_GOAL := help
SHELL := /bin/bash
DATE = $(shell date +%Y-%m-%d:%H:%M:%S)

APP_VERSION_FILE = app/version.py

GIT_BRANCH ?= $(shell git symbolic-ref --short HEAD 2> /dev/null || echo "detached")
GIT_COMMIT ?= $(shell git rev-parse HEAD)

DOCKER_BUILDER_IMAGE_NAME = govuk/notify-api-builder:master
DOCKER_TTY ?= $(if ${JENKINS_HOME},,t)

BUILD_TAG ?= notifications-api-manual
BUILD_NUMBER ?= 0
DEPLOY_BUILD_NUMBER ?= ${BUILD_NUMBER}
BUILD_URL ?=

DOCKER_CONTAINER_PREFIX = ${USER}-${BUILD_TAG}

CF_API ?= api.cloud.service.gov.uk
CF_ORG ?= govuk-notify
CF_SPACE ?= ${DEPLOY_ENV}
CF_HOME ?= ${HOME}
$(eval export CF_HOME)

CF_MANIFEST_FILE = manifest-$(firstword $(subst -, ,$(subst notify-,,${CF_APP})))-${CF_SPACE}.yml

NOTIFY_CREDENTIALS ?= ~/.notify-credentials

.PHONY: help
help:
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: check-env-vars
check-env-vars: ## Check mandatory environment variables
	$(if ${DEPLOY_ENV},,$(error Must specify DEPLOY_ENV))

.PHONY: preview
preview: ## Set environment to preview
	$(eval export DEPLOY_ENV=preview)
	@true

.PHONY: staging
staging: ## Set environment to staging
	$(eval export DEPLOY_ENV=staging)
	@true

.PHONY: production
production: ## Set environment to production
	$(eval export DEPLOY_ENV=production)
	@true

.PHONY: generate-version-file
generate-version-file: ## Generates the app version file
	@echo -e "__travis_commit__ = \"${GIT_COMMIT}\"\n__time__ = \"${DATE}\"\n__travis_job_number__ = \"${BUILD_NUMBER}\"\n__travis_job_url__ = \"${BUILD_URL}\"" > ${APP_VERSION_FILE}

.PHONY: build-paas-artifact
build-paas-artifact:  ## Build the deploy artifact for PaaS
	rm -rf target
	mkdir -p target
	zip -y -q -r -x@deploy-exclude.lst target/notifications-api.zip ./

.PHONY: upload-paas-artifact
upload-paas-artifact: ## Upload the deploy artifact for PaaS
	$(if ${DEPLOY_BUILD_NUMBER},,$(error Must specify DEPLOY_BUILD_NUMBER))
	$(if ${JENKINS_S3_BUCKET},,$(error Must specify JENKINS_S3_BUCKET))
	aws s3 cp --region eu-west-1 --sse AES256 target/notifications-api.zip s3://${JENKINS_S3_BUCKET}/build/notifications-api/${DEPLOY_BUILD_NUMBER}.zip

.PHONY: test
test: generate-version-file ## Run tests
	./scripts/run_tests.sh

.PHONY: freeze-requirements
freeze-requirements: ## Pin all requirements including sub dependencies into requirements.txt
	rm -rf venv-freeze
	virtualenv -p python3 venv-freeze
	$$(pwd)/venv-freeze/bin/pip install -r requirements-app.txt
	echo '# pyup: ignore file' > requirements.txt
	echo '# This file is autogenerated. Do not edit it manually.' >> requirements.txt
	cat requirements-app.txt >> requirements.txt
	echo '' >> requirements.txt
	$$(pwd)/venv-freeze/bin/pip freeze -r <(sed '/^--/d' requirements-app.txt) | sed -n '/The following requirements were added by pip freeze/,$$p' >> requirements.txt
	rm -rf venv-freeze

.PHONY: test-requirements
test-requirements:
	@diff requirements-app.txt requirements.txt | grep '<' \
	    && { echo "requirements.txt doesn't match requirements-app.txt."; \
	         echo "Run 'make freeze-requirements' to update."; exit 1; } \
|| { echo "requirements.txt is up to date"; exit 0; }

.PHONY: coverage
coverage: ; ## don't do anything

.PHONY: prepare-docker-build-image
prepare-docker-build-image: generate-version-file ## Prepare the Docker builder image
	docker build -f docker/Dockerfile \
		--build-arg HTTP_PROXY="${HTTP_PROXY}" \
		--build-arg HTTPS_PROXY="${HTTP_PROXY}" \
		--build-arg NO_PROXY="${NO_PROXY}" \
		-t ${DOCKER_BUILDER_IMAGE_NAME} \
		.

.PHONY: build-with-docker
build-with-docker: ; ## don't do anything

.PHONY: test-with-docker
test-with-docker: prepare-docker-build-image create-docker-test-db ## Run tests inside a Docker container
	@docker run -i${DOCKER_TTY} --rm \
		--name "${DOCKER_CONTAINER_PREFIX}-test" \
		--link "${DOCKER_CONTAINER_PREFIX}-db:postgres" \
		-e SQLALCHEMY_DATABASE_URI=postgresql://postgres:postgres@postgres/test_notification_api \
		-e GIT_COMMIT=${GIT_COMMIT} \
		-e BUILD_NUMBER=${BUILD_NUMBER} \
		-e BUILD_URL=${BUILD_URL} \
		-e http_proxy="${HTTP_PROXY}" \
		-e HTTP_PROXY="${HTTP_PROXY}" \
		-e https_proxy="${HTTPS_PROXY}" \
		-e HTTPS_PROXY="${HTTPS_PROXY}" \
		-e NO_PROXY="${NO_PROXY}" \
		${DOCKER_BUILDER_IMAGE_NAME} \
		make test

.PHONY: create-docker-test-db
create-docker-test-db: ## Start the test database in a Docker container
	docker rm -f ${DOCKER_CONTAINER_PREFIX}-db 2> /dev/null || true
	@docker run -d \
		--name "${DOCKER_CONTAINER_PREFIX}-db" \
		-e POSTGRES_PASSWORD="postgres" \
		-e POSTGRES_DB=test_notification_api \
		postgres:9.5
	sleep 3

# FIXME: CIRCLECI=1 is an ugly hack because the coveralls-python library sends the PR link only this way
.PHONY: coverage-with-docker
coverage-with-docker: prepare-docker-build-image ## Generates coverage report inside a Docker container
	@docker run -i${DOCKER_TTY} --rm \
		--name "${DOCKER_CONTAINER_PREFIX}-coverage" \
		-e COVERALLS_REPO_TOKEN=${COVERALLS_REPO_TOKEN} \
		-e CIRCLECI=1 \
		-e CI_NAME=${CI_NAME} \
		-e CI_BUILD_NUMBER=${BUILD_NUMBER} \
		-e CI_BUILD_URL=${BUILD_URL} \
		-e CI_BRANCH=${GIT_BRANCH} \
		-e CI_PULL_REQUEST=${CI_PULL_REQUEST} \
		-e http_proxy="${HTTP_PROXY}" \
		-e HTTP_PROXY="${HTTP_PROXY}" \
		-e https_proxy="${HTTPS_PROXY}" \
		-e HTTPS_PROXY="${HTTPS_PROXY}" \
		-e NO_PROXY="${NO_PROXY}" \
		${DOCKER_BUILDER_IMAGE_NAME} \
		make coverage

.PHONY: clean-docker-containers
clean-docker-containers: ## Clean up any remaining docker containers
	docker rm -f $(shell docker ps -q -f "name=${DOCKER_CONTAINER_PREFIX}") 2> /dev/null || true

.PHONY: clean
clean:
	rm -rf node_modules cache target venv .coverage build tests/.cache

.PHONY: cf-login
cf-login: ## Log in to Cloud Foundry
	$(if ${CF_USERNAME},,$(error Must specify CF_USERNAME))
	$(if ${CF_PASSWORD},,$(error Must specify CF_PASSWORD))
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	@echo "Logging in to Cloud Foundry on ${CF_API}"
	@cf login -a "${CF_API}" -u ${CF_USERNAME} -p "${CF_PASSWORD}" -o "${CF_ORG}" -s "${CF_SPACE}"

.PHONY: generate-manifest
generate-manifest:
	$(if ${CF_APP},,$(error Must specify CF_APP))
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	$(if $(shell which gpg2), $(eval export GPG=gpg2), $(eval export GPG=gpg))
	$(if ${GPG_PASSPHRASE_TXT}, $(eval export DECRYPT_CMD=echo -n $$$${GPG_PASSPHRASE_TXT} | ${GPG} --quiet --batch --passphrase-fd 0 --pinentry-mode loopback -d), $(eval export DECRYPT_CMD=${GPG} --quiet --batch -d))

	@jinja2 --strict manifest.yml.j2 \
	    -D environment=${CF_SPACE} \
	    -D CF_APP=${CF_APP} \
	    --format=yaml \
	    <(${DECRYPT_CMD} ${NOTIFY_CREDENTIALS}/credentials/${CF_SPACE}/paas/environment-variables.gpg) 2>&1

.PHONY: cf-deploy
cf-deploy: ## Deploys the app to Cloud Foundry
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	$(if ${CF_APP},,$(error Must specify CF_APP))
	cf target -o ${CF_ORG} -s ${CF_SPACE}
	@cf app --guid ${CF_APP} || exit 1

	# cancel any existing deploys to ensure we can apply manifest (if a deploy is in progress you'll see ScaleDisabledDuringDeployment)
	cf v3-cancel-zdt-push ${CF_APP} || true

	cf v3-apply-manifest ${CF_APP} -f <(make -s generate-manifest)
	CF_STARTUP_TIMEOUT=10 cf v3-zdt-push ${CF_APP} --wait-for-deploy-complete  # fails after 5 mins if deploy doesn't work


.PHONY: cf-deploy-api-db-migration
cf-deploy-api-db-migration:
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	cf target -o ${CF_ORG} -s ${CF_SPACE}
	cf push notify-api-db-migration --no-route -f <(make -s CF_APP=notify-api-db-migration generate-manifest)
	cf run-task notify-api-db-migration "flask db upgrade" --name api_db_migration

.PHONY: cf-check-api-db-migration-task
cf-check-api-db-migration-task: ## Get the status for the last notify-api-db-migration task
	@cf curl /v3/apps/`cf app --guid notify-api-db-migration`/tasks?order_by=-created_at | jq -r ".resources[0].state"

.PHONY: cf-rollback
cf-rollback: ## Rollbacks the app to the previous release
	$(if ${CF_APP},,$(error Must specify CF_APP))
	cf v3-cancel-zdt-push ${CF_APP}

.PHONY: cf-push
cf-push:
	$(if ${CF_APP},,$(error Must specify CF_APP))
	cf target -o ${CF_ORG} -s ${CF_SPACE}
	cf push ${CF_APP} -f <(make -s generate-manifest)

.PHONY: check-if-migrations-to-run
check-if-migrations-to-run:
	@echo $(shell python3 scripts/check_if_new_migration.py)
