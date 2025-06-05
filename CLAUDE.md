# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains Docker configurations and custom images, primarily focused on a dynamic PHP-FPM container with Nginx, plus a collection of ready-to-use Docker Compose setups for various services.

## Key Architecture Components

### Custom PHP Image (`images/php/8.4/`)
- **Base**: PHP 8.4-FPM with Nginx and Supervisor
- **Dynamic Configuration**: Uses remote configuration scripts from `scripts/` directory
- **Entrypoint Logic**: Downloads and sources `php.sh` from GitHub for dynamic configuration generation
- **Key Features**: 
  - Environment-based PHP/FPM configuration
  - Auto-detects and sets up Laravel projects
  - System resource-based FPM pool sizing
  - Extensible PHP extension management via env vars

### Configuration Architecture
- **`scripts/php.sh`**: Central configuration script with functions for:
  - PHP INI generation based on environment variables
  - PHP-FPM pool configuration with automatic resource calculation
  - Laravel project setup and dependency management
  - System resource detection and optimization
- **`entrypoint.sh`**: Downloads and sources the remote configuration script, then starts services via Supervisor

### Docker Compose Collections (`docker-compose/`)
Ready-to-use stacks for:
- Database systems (MySQL, PostgreSQL, MongoDB, Redis)
- Admin interfaces (phpMyAdmin, Adminer, MongoDB Express)
- Development tools (Portainer, n8n, Mailhog)
- Vector databases (Milvus, Qdrant)
- Web servers (Nginx, Caddy)
- Application frameworks (Strapi, Nextcloud)

## Common Development Tasks

### Building the Custom PHP Image
```bash
cd images/php/8.4
docker build -t custom-php:8.4 .
```

### Testing with Docker Compose
```bash
cd images/php/8.4
docker-compose up -d
```

### Using Pre-built Services
```bash
cd docker-compose/<service-name>
docker-compose up -d
```

### Environment Variables for PHP Container
- **PHP Configuration**: `PHP_MEMORY_LIMIT`, `PHP_UPLOAD_MAX_FILESIZE`, `PHP_MAX_EXECUTION_TIME`
- **FPM Pool**: `FPM_PM`, `FPM_PM_MAX_CHILDREN`, `FPM_PM_START_SERVERS`
- **Extensions**: `PHP_EXTENSION_<NAME>=1` to enable extensions
- **Application**: `APP_DIR` (default: `/var/www/html`)

## Configuration Management

The system uses a centralized configuration approach where:
1. `entrypoint.sh` fetches `scripts/php.sh` from GitHub
2. Configuration functions generate PHP INI, FPM pool, and setup Laravel
3. Services start via Supervisor with generated configurations

This allows the same image to be used across different projects with environment-specific configurations without rebuilding.