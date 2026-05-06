# Create SemVer Releases

This action creates a set of releases using the SemVer format.

## How to use this action

Create a workflow in your repository incorporating this action.

```yaml
# File: .github/workflows/release-version.yaml
name: Create versioned release

permissions:
  contents: write
  packages: write

on:
  workflow_dispatch:
    inputs:
      update-type:
        type: choice
        description: Which version you want to increment? Use major, minor or patch
        required: true
        default: patch
        options:
          - major
          - minor
          - patch
      label:
        description: Add Labels. i.e final, alpha, rc
        required: false
      pre-release:
        type: boolean
        description: Pre-release
        required: false
        default: false

jobs:
  release-version:
    name: Create SemVer releases
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@<version>

      - name: Create version releases
        uses: open-climpr/semver-release@<version>
        with:
          update-type: ${{ github.event.inputs.update-type }}
          label: ${{ github.event.inputs.label }}
          pre-release: ${{ github.event.inputs.pre-release }}
```
