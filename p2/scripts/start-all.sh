#!/bin/bash

set -e

for f in confs/*.yaml; do
  vagrant ssh haboudaS -- "sudo kubectl apply -f -" < $f
done
