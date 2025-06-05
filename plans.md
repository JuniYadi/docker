We want create a customize Docker Image for PHP FPM with the following features:

1. it's using nginx as a web server
2. it's has preinstalled php extensions that can be enable or disable using env

what the missing is

1. all still depend on Dockerfile, so everytime we need update config file, we need to rebuild the image
2. we need dynamic configuration for nginx, supervisor, etc. why
   - we want to use the same image for different projects, so we need to be able to change the configuration without rebuilding the image
   - we want to be able to change the configuration without stopping the container

## Tasks

We already have a php image with all in `images/php/8.4`, now we need centralize the configuration files from this directory `scripts`, we already implement `php.sh` that called from `entrypoint.sh`, now we need to implement the following:

1. `nginx.sh` to generate the nginx configuration file
2. `supervisor.sh` to generate the supervisor configuration file
3. `nginx-vhost.sh` to generate the nginx vhost configuration file

what we want to achieve is to have a single entrypoint script that will call all the other scripts to generate the configuration files and start the services.
