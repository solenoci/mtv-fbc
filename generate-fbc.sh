#!/usr/bin/env bash

set -ex

# shellcheck source=opm_utils.sh
source opm_utils.sh

package_name="mtv-operator"

helpFunction()
{
  echo -e "Usage: $0\n"
  echo -e "\t--help:   see all commands of this script\n"
  echo -e "\t--init <OCP_minor>:   init catalog fragment for ocp version from existing index\n\t  example: $0 --init v4.14\n"
  echo -e "\t--render-template <OCP_minor>:   render catalog template for ocp version\n\t  example: $0 --render-template v4.14\n"
  exit 1
}

dockerfile()
{   
    suffix="-rhel9"
    if [[ "$1" =~ ^v4.1(1|2|3|4)$ ]]; then suffix="" ; fi

    cat <<EOT > "$1"/catalog.Dockerfile
# The base image is expected to contain
# /bin/opm (with a serve subcommand) and /bin/grpc_health_probe
FROM registry.redhat.io/openshift4/ose-operator-registry${suffix}:$1

# Configure the entrypoint and command
ENTRYPOINT ["/bin/opm"]
CMD ["serve", "/configs", "--cache-dir=/tmp/cache"]

# Copy declarative config root into image at /configs and pre-populate serve cache
ADD catalog /configs
RUN ["/bin/opm", "serve", "/configs", "--cache-dir=/tmp/cache", "--cache-only"]

# Set DC-specific label for the location of the DC root directory
# in the image
LABEL operators.operatorframework.io.index.configs.v1=/configs
EOT
}

cmd="$1"
case $cmd in
  "--help")
    helpFunction
  ;;
  "--init")
    frag=$2
    if [ -z "$frag" ]
    then
      echo "Please specify OCP minor, eg: v4.14"
      exit 1
    fi
    mkdir -p "${frag}/catalog/${package_name}/"
    dockerfile "$frag"
# shellcheck disable=SC2086
    FROMV=$(grep FROM "${frag}"/catalog.Dockerfile)
    OCPV=${FROMV##*:}
    from=registry.redhat.io/redhat/redhat-operator-index:${OCPV}
    ./opm migrate "$from" "./catalog-migrate-${frag}"
    ./opm alpha convert-template basic "./catalog-migrate-${frag}/${package_name}/catalog.json" > "${frag}/catalog-template.json"
    ./opm alpha render-template basic $(opm_alpha_params "${frag}") "${frag}/catalog-template.json" > "${frag}/catalog/${package_name}/catalog.json"
    rm -rf "./catalog-migrate-${frag}"
  ;;
  "--render-template")
    frag=$2
    if [ -z "$frag" ]
    then
      echo "Please specify OCP minor, eg: v4.14"
      exit 1
    fi
    ./opm alpha render-template basic $(opm_alpha_params "${frag}") "${frag}/catalog-template.json" > "${frag}/catalog/${package_name}/catalog.json"
    ;;
  *)
    echo "$cmd not one of the allowed flags"
    helpFunction
  ;;
esac
