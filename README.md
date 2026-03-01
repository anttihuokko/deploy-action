# deploy-action

## Development

### Edit Security Config Vault

You need to have bw unlocked.

```
ansible-vault edit --vault-password-file=vault-password.sh test-security-config.vault
```

### Docker Image Testing

Docker image can be build and tested locally.

Build new local version of the Docker image.

```
docker build --tag dev/deploy-action:latest .
```

Run local version of the Docker image

```
docker run \
--name deploy-action-test \
--rm \
--cap-add CAP_NET_ADMIN \
--workdir /__workspace \
-v .:"/__workspace":ro \
dev/deploy-action:latest \
--vault-password=$(./vault-password.sh) \
--security-config='test-security-config.vault' \
--ssh-command=uptime
```

```
docker run \
--name deploy-action-test \
--rm \
--cap-add CAP_NET_ADMIN \
--workdir /__workspace \
-v ../env-home:"/__workspace":ro \
dev/deploy-action:latest \
--vault-password=$(../env-home/vault-password.sh) \
--security-config=$(cat ../env-home/server-security-config.vault | tr '\n' '|') \
--ansible-playbook=server.yml \
--ansible-tags=system,users \
--ansible-dry-run=true
```

### Local Action Testing

Github action can be tested locally using [nektos/act](https://nektosact.com/)
Installation: Download the `act` binary from website and add it to ~/.local/bin directory.

Get list of avalilable jobs.

```
act --list
```

Build image and deploy it to ghcr.io Docker repo.
In order to permit pushing images to Docker repository you need to create a GitHub token with `write:packages` permission.
To stop act from prompting for the token every time you can store the token to an environment variable: ` export GITHUB_TOKEN=<TOKEN>`. Rember to prefix the command with a space so that the command in not stored in shell history.

```
act -s GITHUB_TOKEN -j build-image
```

Locally run action.

```
VAULT_PASSWORD="$(./vault-password.sh)" \
SECURITY_CONFIG=$(cat test-security-config.vault | tr '\n' '|') \
bash -c 'act -s VAULT_PASSWORD -s SECURITY_CONFIG -j test'
```

## Releasing

The image version number needs to be manually updated to `action.yml`. New release can be triggered by adding a new version tag.

```
git tag v1.0 && git push origin v1.0
```
