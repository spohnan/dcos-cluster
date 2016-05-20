#!/usr/bin/env bash
#
# This script will assist with the bootstrap of a new dcos cluster
#
# Usage: bootstrap.sh
# 		--provider [aws|gce]
# 		--prefix [NODE_NAME_PREFIX]
# 		--vars [variable file name]
# 		--action [CONFIG_STEP]
# 		--tags [ comma separated task tags ]      # optional
# 		--skip-tags [ comma separated task tags ] # optional
#		--verbose                                 # optionally run ansible with -vvv

# Parse arguments
declare -A ARGS
# Defaults
ARGS[provider]="aws"
while [ $# -gt 0 ]; do
	# Trim the first two chars off of the arg name ex: --foo
	case "$1" in
		*) NAME="${1:2}"; shift; ARGS[$NAME]="${1-true}" ;;
	esac
	shift
done

# Ensure we've specified the cluster name prefix
if [ -z "${ARGS[prefix]}" ] && [ "${ARGS[action]}" != "list-inventory" ]; then
	echo "No cluster name given ... exiting"
	exit
fi

# The cluster name used to prefix all instance names ex: m1-master or m1-node-065245
CLUSTER="tag_Cluster=${ARGS[prefix]}"
if [ "${ARGS[provider]}" == "aws" ]; then
	CLUSTER="ec2_${CLUSTER}" # tags are prefaced with ec2 when using AWS
fi

list_inventory() {
	case "${ARGS[provider]}" in
		"aws") hosts/aws/ec2.py --list --refresh-cache ;;
		"gce") hosts/gce/gce.py --list --pretty ;;
	esac
}

run_playbook() {
	[[ ! -z "${ARGS[tags]}" ]] && tags="--tags ${ARGS[tags]}"
	[[ ! -z "${ARGS[skip-tags]}" ]] && skip_tags="--skip-tags ${ARGS[skip-tags]}"
	pipeline="true"; ([ "$1" == "provision" ] || [ "$1" == "prep" ]) && pipeline="false"
	ansible-playbook ${ARGS[verbose]//true/-vvv} \
		-i hosts/"${ARGS[provider]}" \
		-e $CLUSTER \
		-e "cluster_prefix=${ARGS[prefix]}" \
		-e "pipelining=${pipeline}" \
		${intial_build} \
		"${ARGS[provider]}-${1}.yml" \
		${tags} ${skip_tags} \
		 --extra-vars="varfile=${ARGS[vars]}"
}

# Execute the action command passed to the script
# ---------------------------------------------------------------------------
#  - Special actions like list-inventory are mapped to internal functions
#  - Multi-step playbook actions are run in a loop
#  - Individual playbook names can be specified and they will be run
case "${ARGS[action]}" in
	"ami")
		STEPS=( "ami-provision" "ami-configure" )
		for step in "${STEPS[@]}"; do
			run_playbook $step
			list_inventory > /dev/null 2>&1 # Update cache
		done ;;
	"cluster")
		STEPS=( "provision" "configure" )
		for step in "${STEPS[@]}"; do
			run_playbook $step
			list_inventory > /dev/null 2>&1 # Update cache
		done ;;
	"list-inventory") list_inventory ;;
	"ping") ansible -i hosts/"${ARGS[provider]}" "tag_Cluster_${ARGS[prefix]}" -m ping;;
	*) run_playbook "${ARGS[action]}" ;; # Anything else should be a playbook
esac
