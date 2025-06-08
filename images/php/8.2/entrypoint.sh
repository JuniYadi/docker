#!/bin/bash

# Enhanced entrypoint script for NGINX Unit + PHP CLI support

case "$1" in
    web)
        echo "Starting NGINX Unit web server..."
        exec unitd --no-daemon --control unix:/var/run/control.sock
        ;;
    cli)
        echo "Running PHP CLI command: ${@:2}"
        exec php "${@:2}"
        ;;
    composer)
        echo "Running Composer: ${@:2}"
        exec composer "${@:2}"
        ;;
    bash)
        echo "Starting interactive bash shell..."
        exec /bin/bash
        ;;
    *)
        echo "Usage: $0 {web|cli|composer|bash}"
        echo "  web      - Start NGINX Unit web server (default)"
        echo "  cli      - Run PHP CLI commands"
        echo "  composer - Run Composer commands"
        echo "  bash     - Start interactive bash shell"
        exit 1
        ;;
esac
