#!/usr/bin/env bash
set -e

IMAGE=fuzzpipe

case "$1" in
  build)
    docker build -t $IMAGE -f docker/Dockerfile .
    ;;

  shell)
    docker run -it --rm -v $(pwd):/workspace $IMAGE
    ;;

  *)
    echo "Usage:"
    echo "./fuzz/run.sh build"
    echo "./fuzz/run.sh shell"
    ;;
esac
