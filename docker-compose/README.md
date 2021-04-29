## NodeJS Install

```
docker run --rm --interactive --tty --volume %cd%:/app --workdir /app node:14-alpine npm install
```

## Composer Install

```
docker run --rm --interactive --tty --volume %cd%:/app --workdir /app composer composer install --ignore-platform-reqs
```
