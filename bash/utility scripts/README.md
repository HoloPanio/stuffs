# Utility Scripts
This folder is for quick utility scripts that I use on linux in day to day workflows.

## What this script is for
`debian-apt-packages.bash` replaces `/etc/apt/sources.list` with the official Debian 13 (Trixie) repositories and creates a timestamped backup of your existing file first.

I keep this script here because after using the Debian installer ISO, apt can end up referencing the repository on the install disk instead of the normal remote Debian repos. This gives me a quick way to switch back to a known-good online repo setup without manually editing system files each time.

## Run the Debian APT sources script from GitHub
Use this command to download and run the script directly from this repo:

```bash
wget -qO- https://raw.githubusercontent.com/HoloPanio/stuffs/main/bash/utility%20scripts/debian-apt-packages.bash | sudo bash
```
