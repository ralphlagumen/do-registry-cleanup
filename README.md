## Usage

To use this action, first install `doctl` and authenticate with DigitalOcean.

```yaml
- name: Install doctl
  uses: digitalocean/action-doctl@v2
  with:
    token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

- name: Login to DigitalOcean Registry
  run: doctl registry login --expiry-seconds 3600 # Adjust expiry as needed