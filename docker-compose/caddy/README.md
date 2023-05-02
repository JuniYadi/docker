# Caddy Server

Caddy with Custom Modules DNS

- Cloudflare DNS

## Custom Build

### Build XCaddy

```
docker build -t caddy .
```

### Copy From Docker to Hosts

```
docker create --name caddy caddy
docker cp caddy:/usr/bin/caddy /usr/bin/caddy
docker rm -f caddy
```

## Install Caddy

### Debian/Ubuntu

```
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

## Custom XCaddy Usage

Package support files for custom builds for Debian/Ubuntu/Raspbian

this procedure aims to simplify running custom caddy binaries while keeping support files from the caddy package.

This procedure allows users to take advantage of the default configuration, systemd service files and bash-completion from the official package.

Requirements:

1. Install caddy package according to these instructions
2. Build your custom caddy binary according to the procedure listed in this document. (see above)
3. Your custom caddy binary should be located in the current directory.

```
sudo dpkg-divert --divert /usr/bin/caddy.default --rename /usr/bin/caddy
sudo mv ./caddy /usr/bin/caddy.custom
sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.default 10
sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.custom 50
```

`dpkg-divert` will move `/usr/bin/caddy` binary to `/usr/bin/caddy.default` and put a diversion in place in case any package want to install a file to this location.

`update-alternatives` will create a symlink from the desired caddy binary to `/usr/bin/caddy`

You can change between the custom and default caddy binaries by executing

```
update-alternatives --config caddy
```

and following the on screen information.
