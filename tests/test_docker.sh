#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-08 14:38:37 +0000 (Thu, 08 Dec 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
DEBUG="${DEBUG:-}"
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "$0")" && pwd)"

cd "$srcdir/.."

. "bash-tools/docker.sh"
. "bash-tools/utils.sh"

section "Docker Image"

export DOCKER_IMAGE="harisekhon/nagios-plugins"
export DOCKER_IMAGE_TAGS="latest centos debian ubuntu alpine"
export DOCKER_IMAGES=(harisekhon/tools harisekhon/pytools harisekhon/nagios-plugins)
if is_CI; then
    export DOCKER_IMAGES="$(ci_sample ${DOCKER_IMAGES[*]})"
fi

stdout="/dev/stdout"
if is_CI; then
    stdout="/dev/null"
fi

if is_docker_available; then
    [ -n "${NO_DOCKER:-}" ] && exit 0
    if [ -z "${NO_PULL:-}" ]; then
        echo docker pull "$DOCKER_IMAGE"
        docker pull "$DOCKER_IMAGE" > $stdout
        for image in ${DOCKER_IMAGES[*]}; do
            echo docker pull "$image"
            docker pull "$image" > $stdout
        done
        for tag in $DOCKER_IMAGE_TAGS; do
            echo docker pull "$DOCKER_IMAGE:$tag"
            docker pull "$DOCKER_IMAGE:$tag" > $stdout
        done
    fi
    hr

    run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest"

    for image in ${DOCKER_IMAGES[*]}; do
        max_size=$((600 * 1024 * 1024))
#        if grep nagios <<< "$image"; then
#            max_size=$((600 * 1024 * 1024))
#        fi
        if ! [[ "$image" =~ : ]]; then
            image="$image:latest"
        fi
        run ./check_docker_image.py --docker-image "$image" --warning "$max_size"
    done
    for tag in $DOCKER_IMAGE_TAGS; do
        run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((800 * 1024 * 1024))

        echo "checking thresholds fail as expected:"
        run_fail 1 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((300 * 1024 * 1024))

        run_fail 2 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --critical $((300 * 1024 * 1024))
    done
    echo "getting docker image id"
    # This fails set -e, possibly because docker images command is interrupted by the abrupt exit of awk
    set +e
    id="$(docker images | awk "/^${DOCKER_IMAGE//\//\\/}.*latest/{print \$3; exit}")"
    set -e
    if [ -z "$id" ]; then
        echo "FAILED to get docker image id, debug pipeline"
        exit 1
    fi
    hr
    echo "testing against expected id of $id"
    run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "$id"

    echo "testing intentional id failure:"
    run_fail 2 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "wrongid"

    run_fail 3 docker run --rm -e DEBUG="$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl --help

    run docker run --rm -e DEBUG="$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl -H google.com

    echo
    echo "Completed $run_count Docker tests"
    echo
    echo "now checking all programs within the docker image run --help without missing dependencies:"
    run docker run --rm -e DEBUG="$DEBUG" -e NO_GIT=1 -e TRAVIS="${TRAVIS:-}" "$DOCKER_IMAGE" tests/help.sh
fi
