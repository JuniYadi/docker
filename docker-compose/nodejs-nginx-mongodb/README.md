# Docker Node NextJS + MongoDB

## Next JS Init

```bash
docker run --rm --interactive --tty \
    --volume "$PWD":/code \
    --workdir /code \
    node:12-alpine \
    yarn create next-app
```

## Yarn Install

```bash
docker run --rm --interactive --tty \
    --volume "$PWD"/code:/code \
    --workdir /code \
    node:12-alpine \
    yarn install
```

## Running

```
docker-compose up
```
