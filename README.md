# scripts

A shell script that downloads and installs binaries from GitHub releases.

Set INSTALLER_TOOL and INSTALLER_OWNER environment variables to specify the tool and repository owner,
then run the script to automatically detect your platform and install the latest release binary.

Supports version selection, custom output directories, and dry-run mode via command-line flags or environment variables.
