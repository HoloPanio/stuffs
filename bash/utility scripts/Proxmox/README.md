# Proxmox
This folder is for Proxmox utility scripts that help me fix common host configuration issues quickly.

## What this script is for
`update-hostname.bash` updates a standalone Proxmox VE node hostname by replacing `/etc/hostname`, updating the management IP mapping in `/etc/hosts`, and repairing stale Proxmox guest config paths under `/etc/pve/nodes/`, while creating backups of the files first.

I keep this script here because a Proxmox host sometimes needs to be renamed after initial setup, and a partial rename can leave VMs or containers under the old node path. This gives me a quick repeatable way to switch a standalone node to the correct hostname and repair that stale node mapping without manually editing each file every time.

This script is only for standalone Proxmox VE nodes. Do not use it on a node that belongs to a cluster.

## Run the Update Hostname script from GitHub
Use this command to download and run the script directly from this repo:

```bash
wget -qO- https://raw.githubusercontent.com/HoloPanio/stuffs/main/bash/utility%20scripts/Proxmox/update-hostname.bash | sudo bash -s -- pve01 pve01.lab.example 192.168.10.10
```