
# DigitalOcean Registry Cleanup GitHub Action

`ralphlagumen/do-registry-cleanup` is a GitHub Action that automates the cleanup of container images in DigitalOcean's Container Registry based on a specified age threshold. This action is useful for managing and conserving storage space by removing older, unused images.

## Features

- Deletes images in DigitalOcean Container Registry older than a specified age.
- Supports age thresholds in days (`d`), weeks (`w`), and months (`m`).
- Users handle DigitalOcean authentication and `doctl` installation, keeping the action focused on cleanup.

## Setup

### Prerequisites

1. **DigitalOcean API Token**: Obtain an API token from [DigitalOcean](https://cloud.digitalocean.com/account/api/tokens) and add it as a secret named `DIGITALOCEAN_ACCESS_TOKEN` in your GitHub repository.

2. **Install `doctl` and Authenticate**: This action requires `doctl` to be installed and authenticated. You can set this up with the following steps:

```yaml
- name: Install doctl
    uses: digitalocean/action-doctl@v2
    with:
    token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

- name: Login to DigitalOcean Registry
    run: doctl registry login --expiry-seconds 3600 # Adjust expiry as needed
```

### Adding the Action to Your Workflow

After setting up authentication, add the `ralphlagumen/do-registry-cleanup` action to your workflow to delete images based on age.

Example usage:

```yaml
- name: Cleanup Registry
  uses: ralphlagumen/do-registry-cleanup@v1.0.2
  with:
    age: '1m'  # Specify the age threshold for deleting images, e.g., '7d', '2w', or '1m'
```

## Inputs

- **`age`**: Age threshold for deleting images, supporting days (`d`), weeks (`w`), and months (`m`). Example values:
  - `7d` - Deletes images older than 7 days
  - `2w` - Deletes images older than 2 weeks
  - `1m` - Deletes images older than 1 month

## Validation Process

The action includes several validation steps to ensure proper usage:

1. **Check if `doctl` is Installed**: If `doctl` is not installed, the action will display an error and exit.

2. **Check if `doctl` is Authenticated**: If `doctl` is not authenticated, the action will prompt you to log in to DigitalOcean using `doctl auth init` or `doctl registry login`.

3. **Validate `age` Input Format**: The action checks that the `age` parameter is provided in a valid format (`<number>d`, `<number>w`, or `<number>m`). Invalid formats will result in an error, with guidance on accepted formats.

### Example Error Messages

- **Missing `doctl`**: "Error: doctl is not installed. Please install doctl before running this action."
- **Unauthenticated `doctl`**: "Error: doctl is not authenticated. Please run 'doctl auth init' or 'doctl registry login' before using this action."
- **Invalid `age` Format**: "Error: Invalid age format. Use a valid format such as '7d' for 7 days, '2w' for 2 weeks, or '1m' for 1 month."

## Testing Locally with `MOCK_MODE`

To test the action without interacting with a real DigitalOcean registry, you can enable `MOCK_MODE` by setting an environment variable. This mode will simulate `doctl` responses and avoid actual deletions.

```yaml
- name: Cleanup Registry (Mock Mode)
  uses: ralphlagumen/do-registry-cleanup@v1.0.2
  env:
    MOCK_MODE: true
  with:
    age: '1m'
```

## Complete Workflow Example

Here’s a complete example of how to set up this action in your workflow:

```yaml
name: DigitalOcean Registry Cleanup

on:
  schedule:
    - cron: "0 3 * * *"  # Runs daily at 3:00 AM UTC, adjust as needed

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Install doctl
        uses: digitalocean/action-doctl@v2
        with:
          token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

      - name: Login to DigitalOcean Registry
        run: doctl registry login --expiry-seconds 3600

      - name: Cleanup Registry
        uses: ralphlagumen/do-registry-cleanup@v1.0.2
        with:
          age: '1m'
```

## Notes

- This action does not manage `doctl` installation or authentication directly. Ensure `doctl` is properly installed and authenticated before using the cleanup step.
- Adjust the `cron` schedule to control when the cleanup action runs (e.g., daily, weekly).

## License

This project is licensed under the MIT License.