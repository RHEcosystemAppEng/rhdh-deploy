################################################
# Makefile for deploying Red Hat Developer Hub #
################################################

##########################
# Customizable Variables #
##########################
BIN_AWK ?= awk ##@ Set a custom 'awk' binary path if not in PATH
BIN_HELM ?= helm ##@ Set a custom 'helm' binary path if not in PATH
BIN_OC ?= oc ##@ Set a custom 'oc' binary path if not in PATH
BIN_YQ ?= yq ##@ Set a custom 'yq' binary path if not in PATH
FILE_CONFIG_SECRET ?= deploy/secrets/rhdh-secrets.yml ##@ Path for configuration secret, defaults to 'deploy/secrets/rhdh-secrets.yml'
FILE_PULL_SECRET ?= deploy/secrets/rhdh-pull-secret.yml ##@ Path for the Quay.io secret, defaults to 'deploy/secrets/rhdh-pull-secret.yml'
FILE_RHDH_CONFIG_STANDALONE ?= deploy/configs/app-config-rhdh-standalone.yml ##@ Path for the RHDH standalone configuration file, defaults to 'deploy/configs/app-config-rhdh-standalone.yml'
FILE_RHDH_CONFIG_INTEGRATION_GH ?= deploy/configs/app-config-rhdh-integration-gh.yml ##@ Path for the RHDH GitHub integration configuration file, defaults to 'deploy/configs/app-config-rhdh-integration-gh.yml'
HELM_RELEASE_NAME ?= rhdh-devel-release ##@ Name of the desired Helm release, defaults to 'rhdh-devel-release'
HELM_REPO_NAME ?= openshift-helm-charts ##@ Name of the Helm repository record for charts.openshift.io, defaults to 'openshift-helm-charts'
HELM_OPTS ?= ##@ Optionally include extra helm options when deploying
KUBE_CONTEXT ?= ##@ Optionally set a kubeconfig context to use with the various tools
PROJECT_NAME ?= rhdh-devel ##@ Set the project/namespace, defaults to 'rhdh-devel'
PROJECT_EXISTS ?= false ##@ Set to 'true' for using an existing project/namespace

#############
# Constants #
#############
HELM_OCP_REPO := https://charts.openshift.io/
NAME_CONFIG_CONFIGMAP := app-config-rhdh
NAME_CONFIG_CONFIGMAP_KEY := app-config-rhdh.yaml
NAME_CONFIG_SECRET := rhdh-secrets
NAME_HELM_CHART := redhat-developer-hub
NAME_PULL_SECRET := rhdh-pull-secret

########
# Help #
########
default: help
help: verify/tools/awk ## Show this help message
	@$(BIN_AWK) 'BEGIN {\
			FS = ".*##@";\
			print "\033[1;31mRed Hat Developer Hub - Development Deployment\033[0m";\
			print "\033[1;32mUsage\033[0m";\
			printf "\t\033[1;37mmake <target> |";\
			printf "\tmake <target> [Variables Set] |";\
            printf "\tmake [Variables Set] <target> |";\
            print "\t[Variables Set] make <target>\033[0m";\
			print "\033[1;32mAvailable Variables\033[0m" }\
		/^(\s|[a-zA-Z_0-9-]|\/)+ \?=.*?##@/ {\
			split($$0,t,"?=");\
			printf "\t\033[1;36m%-35s \033[0;37m%s\033[0m\n",t[1], $$2 | "sort" }'\
		$(MAKEFILE_LIST)
	@$(BIN_AWK) 'BEGIN {\
			FS = ":.*##";\
			SORTED = "sort";\
            print "\033[1;32mAvailable Targets\033[0m"}\
		/^(\s|[a-zA-Z_0-9-]|\/)+:.*?##/ {\
			if($$0 ~ /deploy/)\
				printf "\t\033[1;36m%-35s \033[0;33m%s\033[0m\n", $$1, $$2 | SORTED;\
			else\
				printf "\t\033[1;36m%-35s \033[0;37m%s\033[0m\n", $$1, $$2 | SORTED; }\
		END { \
			close(SORTED);\
			print "\033[1;32mFurther Information\033[0m";\
			print "\t\033[0;37m* Developer Hub images are located under the private \033[1;37mrhdh\033[0;37m namespace,\n\t  access is required for the user creating the pull secret.\33[0m";\
			print "\t\033[0;37m* Information for creating the \033[1;37mGitHub\033[0;37m app can be found here:\n\t  \033[38;5;26mhttps://backstage.io/docs/integrations/github/github-apps/\33[0m";\
			print "\t\033[0;37m* Source document for this Makefile can be found here:\n\t  \033[38;5;26mhttps://docs.google.com/document/d/1EinUJlk7vX-XF3jzJilApqBGcvMoTjp_kTar2OAllMU/edit?usp=sharing\33[0m"}'\
		$(MAKEFILE_LIST)

############################################
# deployment related targets and variables #
############################################
STANDALONE_PREREQUISITES := validate/config/standalone
STANDALONE_PREREQUISITES += validate/secrets/pull
STANDALONE_PREREQUISITES += ocp/check/cluster
STANDALONE_PREREQUISITES += ocp/create/project
STANDALONE_PREREQUISITES += apply/configmaps/standalone
STANDALONE_PREREQUISITES += apply/secrets/pull
STANDALONE_PREREQUISITES += helm/install/standalone

deploy/standalone: $(STANDALONE_PREREQUISITES) ## Deploy Red Hat Developer Hub without any integrations
	@echo "standalone deployment successful"

INTEGRATION_GITHUB_PREREQUISITES := validate/config/integrations/github
INTEGRATION_GITHUB_PREREQUISITES += validate/secrets/config
INTEGRATION_GITHUB_PREREQUISITES += validate/secrets/pull
INTEGRATION_GITHUB_PREREQUISITES += ocp/check/cluster
INTEGRATION_GITHUB_PREREQUISITES += ocp/create/project
INTEGRATION_GITHUB_PREREQUISITES += apply/configmaps/integrations/github
INTEGRATION_GITHUB_PREREQUISITES += apply/secrets/config
INTEGRATION_GITHUB_PREREQUISITES += apply/secrets/pull
INTEGRATION_GITHUB_PREREQUISITES += helm/install/integrations/github

deploy/integrations/github: $(INTEGRATION_GITHUB_PREREQUISITES) ## Deploy Red Hat Developer Hub with GitHub integration
	@echo "standalone deployment successful"

#####################
# various functions #
#####################
define get_cluster_addr
	$(shell $(BIN_OC) get routes -n openshift-console console --output=yaml | $(BIN_YQ) '.spec.host' | $(BIN_AWK) '{gsub(/console-openshift-console./, ""); print}')
endef

define get_helm_base_cmd
	$(eval helmCmd := $(BIN_HELM) upgrade $(HELM_RELEASE_NAME) --atomic --cleanup-on-fail --install\
		-n $(PROJECT_NAME) $(shell echo $(HELM_REPO_NAME) | xargs)/$(NAME_HELM_CHART)\
		--set 'global.clusterRouterBase=$(strip $(call get_cluster_addr))'\
		--set 'upstream.backstage.args={--config,app-config.yaml,--config,app-config.example.yaml,--config,app-config.example.production.yaml}')
	$(if $(KUBE_CONTEXT),$(eval helmCmd := $(helmCmd) --kube-context $(KUBE_CONTEXT)))
	$(helmCmd)
endef

##########################################################
# targets related to the deployment of the rhdh instance #
##########################################################
apply/configmaps/standalone: verify/tools/oc ## Apply the standalone configuration ConfigMap
	$(eval cmapCmd := $(BIN_OC) create configmap $(NAME_CONFIG_CONFIGMAP) -n $(PROJECT_NAME) --from-file $(NAME_CONFIG_CONFIGMAP_KEY)=$(FILE_RHDH_CONFIG_STANDALONE))
ifneq (,$(KUBE_CONTEXT))
	$(eval cmapCmd := $(cmapCmd) --context $(KUBE_CONTEXT))
endif
	@eval $(cmapCmd)
	@echo "standalone configmap applied"

apply/configmaps/integrations/github: verify/tools/oc ## Apply the GitHub integration configuration ConfigMap
	$(eval cmapCmd := $(BIN_OC) create configmap $(NAME_CONFIG_CONFIGMAP) -n $(PROJECT_NAME) --from-file $(NAME_CONFIG_CONFIGMAP_KEY)=$(FILE_RHDH_CONFIG_INTEGRATION_GH))
ifneq (,$(KUBE_CONTEXT))
	$(eval cmapCmd := $(cmapCmd) --context $(KUBE_CONTEXT))
endif
	@eval $(cmapCmd)
	@echo "standalone configmap applied"

apply/secrets/config: verify/tools/oc ## Apply the config Secret resource
	$(eval cfgScrtCmd := $(BIN_OC) apply -n $(PROJECT_NAME) -f $(FILE_CONFIG_SECRET))
ifneq (,$(KUBE_CONTEXT))
	$(eval cfgScrtCmd := $(cfgScrtCmd) --context $(KUBE_CONTEXT))
endif
	@eval $(cfgScrtCmd)
	@echo "config secret applied"

apply/secrets/pull: verify/tools/oc ## Apply the pull Secret resource
	$(eval pullScrtCmd := $(BIN_OC) apply -n $(PROJECT_NAME) -f $(FILE_PULL_SECRET))
ifneq (,$(KUBE_CONTEXT))
	$(eval pullScrtCmd := $(pullScrtCmd) --context $(KUBE_CONTEXT))
endif
	@eval $(pullScrtCmd)
	@echo "pull secret applied"

ocp/check/cluster: verify/tools/oc ## Check OpenShift cluster requirements
	$(eval numRoutesRes := $(shell $(BIN_OC) api-resources --api-group=route.openshift.io --output=name | wc -l))
ifeq ($(numRoutesRes),0)
	$(error Please use an OpenShift cluster)
endif
	@echo "cluster requirements fulfilled"

ocp/create/project: verify/tools/oc ## Create the project/namespace
ifeq ($(PROJECT_EXISTS),true)
	@echo using existing project $(PROJECT_NAME)
else
	$(eval projCmd := $(BIN_OC) new-project $(PROJECT_NAME) > /dev/null)
ifneq (,$(KUBE_CONTEXT))
	$(eval projCmd := $(projCmd) --context $(KUBE_CONTEXT))
endif
	@eval $(projCmd)
	@echo $(PROJECT_NAME) project created
endif

########################
# helm related targets #
########################
.PHONY: helm/add/repo
helm/add/repo: ## Add OpenShift Helm repository to your local environment
	@$(BIN_HELM)  repo add $(HELM_REPO_NAME) $(HELM_OCP_REPO)

helm/install/standalone: verify/tools helm/add/repo ## Install the Developer Hub helm chart without integrations
	 @$(strip $(call get_helm_base_cmd)) $(HELM_OPTS)

helm/install/integrations/github: verify/tools helm/add/repo ## Install the Developer Hub helm chart with GitHub organization integration
	@$(strip $(call get_helm_base_cmd)) \
		--set 'upstream.backstage.extraAppConfig[0].configMapRef=$(NAME_CONFIG_CONFIGMAP)' \
		--set 'upstream.backstage.extraAppConfig[0].filename=$(NAME_CONFIG_CONFIGMAP_KEY)' \
		--set 'upstream.backstage.extraEnvVarsSecrets={$(NAME_CONFIG_SECRET)}' \
		$(HELM_OPTS)

###############################################
# targets used as various tools and utilities #
###############################################
utils/print/callback: verify/tools/awk verify/tools/oc ## print the assumed callback url for creating the GitHub app
	@echo "https://developer-hub-$(strip $(PROJECT_NAME)).$(strip $(call get_cluster_addr))/api/auth/github/handler/frame"

#####################################################
# targets validating the various required resources #
#####################################################
validate/config/standalone: $(FILE_RHDH_CONFIG_STANDALONE) ## Validate the standalone configuration file
	@echo "standalone config file valid"

$(FILE_RHDH_CONFIG_STANDALONE):
	$(error Please create a developer hub standalone config file in '$(FILE_RHDH_CONFIG_STANDALONE)' or specify a custom path using the 'FILE_RHDH_CONFIG_STANDALONE' variable)

validate/config/integrations/github: $(FILE_RHDH_CONFIG_INTEGRATION_GH) ## Validate the GitHub integration configuration file
	@echo "github integration config file valid"

$(FILE_RHDH_CONFIG_INTEGRATION_GH):
	$(error Please create a developer hub GitHub integration config file in '$(FILE_RHDH_CONFIG_INTEGRATION_GH)' or specify a custom path using the 'FILE_RHDH_CONFIG_INTEGRATION_GH' variable)

validate/secrets/pull: $(FILE_PULL_SECRET) verify/tools/yq ## Validate the pull Secret resource
ifneq ($(shell $(BIN_YQ) ".metadata.name" $(FILE_PULL_SECRET)), $(NAME_PULL_SECRET))
	$(error Please use the resource name '$(NAME_PULL_SECRET)' for the secret in '$(FILE_PULL_SECRET)')
endif
ifneq ($(shell $(BIN_YQ) ".kind" $(FILE_PULL_SECRET) | tr '[:upper:]' '[:lower:]'), secret)
	$(error Please use the resource of kind 'Secret' as the pull secret resource)
endif
ifneq ($(shell $(BIN_YQ) ".type" $(FILE_PULL_SECRET) | tr '[:upper:]' '[:lower:]'), kubernetes.io/dockerconfigjson)
	$(error Please use the resource of type 'kubernetes.io/dockerconfigjson' as the pull secret resource)
endif
	@echo "pull secret resource valid"

$(FILE_PULL_SECRET):
	$(error Please create a Quay.io secret resource file in '$(FILE_PULL_SECRET)' or specify a custom path using the 'FILE_PULL_SECRET' variable)

# member 1 is the missing key name
KEY_MISSING_ERR_MSG = Please add a '$(1)' data key to the config secret resource

validate/secrets/config: $(FILE_CONFIG_SECRET) verify/tools/yq ## Validate the config Secret resource
ifneq ($(shell $(BIN_YQ) ".metadata.name" $(FILE_CONFIG_SECRET)), $(NAME_CONFIG_SECRET))
	$(error Please use the resource name '$(NAME_CONFIG_SECRET)' for the secret in '$(FILE_CONFIG_SECRET)')
endif
ifneq ($(shell $(BIN_YQ) ".kind" $(FILE_CONFIG_SECRET) | tr '[:upper:]' '[:lower:]'), secret)
	$(error Please use the resource of kind 'Secret' as the config secret resource)
endif
ifneq ($(shell $(BIN_YQ) ".type" $(FILE_CONFIG_SECRET) | tr '[:upper:]' '[:lower:]'), opaque)
	$(error Please use the resource of type 'Opaque' as the config secret resource)
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_APP_APP_ID")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_APP_APP_ID))
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_APP_CLIENT_ID")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_APP_CLIENT_ID))
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_APP_CLIENT_SECRET")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_APP_CLIENT_SECRET))
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_APP_WEBHOOK_URL")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_APP_WEBHOOK_URL))
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_APP_WEBHOOK_SECRET")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_APP_WEBHOOK_SECRET))
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_APP_PRIVATE_KEY")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_APP_PRIVATE_KEY))
endif
ifneq ($(shell $(BIN_YQ) '.data | has("GITHUB_ENABLED")' $(FILE_CONFIG_SECRET)),true)
	$(error $(call KEY_MISSING_ERR_MSG,GITHUB_ENABLED))
endif
	@echo "config secret resource valid"

$(FILE_CONFIG_SECRET):
	$(error Please create a configuration secret resource file in '$(FILE_CONFIG_SECRET)' or specify a custom path using the 'FILE_CONFIG_SECRET' variable)

##################################################
# targets verifying required tools accessibility #
##################################################
verify/tools: verify/tools/awk verify/tools/helm verify/tools/oc verify/tools/yq ## Verify all the required tools are accessible
	@echo "all tools verified"

# member 1 is the missing tool name, member 2 is the name of the variable used to customize the tool path
TOOL_MISSING_ERR_MSG = Please install '$(1)' or specify a custom path using the '$(2)' variable

.PHONY: verify/tools/awk
verify/tools/awk:
ifeq (,$(shell which $(BIN_AWK) 2> /dev/null ))
	$(error $(call TOOL_MISSING_ERR_MSG,awk,BIN_AWK))
endif

.PHONY: verify/tools/helm
verify/tools/helm:
ifeq (,$(shell which $(BIN_HELM) 2> /dev/null ))
	$(error $(call TOOL_MISSING_ERR_MSG,helm,BIN_HELM))
endif

.PHONY: verify/tools/oc
verify/tools/oc:
ifeq (,$(shell which $(BIN_OC) 2> /dev/null ))
	$(error $(call TOOL_MISSING_ERR_MSG,oc,BIN_OC))
endif

.PHONY: verify/tools/yq
verify/tools/yq:
ifeq (,$(shell which $(BIN_YQ) 2> /dev/null ))
	$(error $(call TOOL_MISSING_ERR_MSG,yq,BIN_YQ))
endif


########################################################
# Makefile section for deploying backstage using openshift template #
########################################################

 DEV_NAMESPACE ?= ${USER}-backstage
 GITHUB_ORGANIZATION  ?= appeng-backstage
 AUTH_GITHUB_CLIENT_ID ?= ''
 AUTH_GITHUB_CLIENT_SECRET ?= ''
 HOSTNAME ?=  $(strip $(call get_cluster_addr))

.PHONY: template/apply
template/apply:
	@if ! oc get project $(DEV_NAMESPACE) >/dev/null 2>&1; then \
		oc new-project $(DEV_NAMESPACE); \
		oc process -f deploy/template/dev-template.yaml  -p DEV_NAMESPACE=$(DEV_NAMESPACE) -p HOSTNAME=$(HOSTNAME) -p GITHUB_ORGANIZATION= $(GITHUB_ORGANIZATION)  -p AUTH_GITHUB_CLIENT_ID=$(AUTH_GITHUB_CLIENT_ID) -p  AUTH_GITHUB_CLIENT_SECRET=$(AUTH_GITHUB_CLIENT_SECRET)  | oc create --save-config -n $(DEV_NAMESPACE) -f -; \
	else \
		oc process -f deploy/template/dev-template.yaml -p DEV_NAMESPACE=$(DEV_NAMESPACE) -p HOSTNAME=$(HOSTNAME) -p GITHUB_ORGANIZATION=$(GITHUB_ORGANIZATION)  -p AUTH_GITHUB_CLIENT_ID=$(AUTH_GITHUB_CLIENT_ID)  -p AUTH_GITHUB_CLIENT_SECRET=$(AUTH_GITHUB_CLIENT_SECRET) | oc apply -n $(DEV_NAMESPACE) -f -; \
	fi

.PHONY: template/clean
template/clean:
	oc process -f deploy/template/dev-template.yaml -p DEV_NAMESPACE=$(DEV_NAMESPACE)  | oc -n $(DEV_NAMESPACE) delete -f -
