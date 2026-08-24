# Third-party notices

The project-development-governance-skills source is released under the MIT License in `LICENSE`.

## Runtime and source dependencies

- PowerShell 5.1 and PowerShell 7 are execution environments supplied by the host operating system. They are not bundled or redistributed by this repository.
- GitHub Actions are workflow-time dependencies only. The workflows use `actions/checkout@v4` and `actions/upload-artifact@v4`; their source, license, and release history are published by [actions/checkout](https://github.com/actions/checkout) and [actions/upload-artifact](https://github.com/actions/upload-artifact). They are not vendored into the Skill package.
- No third-party runtime package, model weight, font, media asset, or generated binary is vendored in this repository.

The machine-readable dependency inventory is [sbom/cyclonedx.json](sbom/cyclonedx.json). Any future dependency must be added there, documented here, and checked for license compatibility before release.
