# Inception of Things

The goal of this project is to learn how to manage kubernetes cluster with K3S and Vagrant.

## Part 1

**TODO:** Find a better way to share tokens

Simply run vagrant:
```bash
cd p1   # from iot's root
vagrant up
```

how do check it works:
```
vagrant ssh haboudaS
sudo kubectl get nodes -o wide  # shows ips and status
```

explanations:
- Vagrant: automates VM creation from a Vagrantfile describing the machine, similiar to what can be found in a docker-compose or a nixos profile. ``vagrant up`` runs the file.
- K3s: lightweight kubernetes, in this setup one node runs as master(server) (control plane for the workers, schedules their workloads, etc), and the others (only one in this case) as slaves(server workers/agents)
- flannel: network overlays used by k3s so pods on different nodes can talk each other. it's bound to a network interface (``eth1``, private interface)

## Part 2

## Part 3
