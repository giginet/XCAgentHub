#!/bin/sh
set -e

# Milepost ships a build tool plugin, and Xcode refuses to run one it has not
# been told to trust — on a fresh Xcode Cloud machine that means the archive
# fails with:
#
#   Plugin "PrepareMilepost" from package "Milepost" must be enabled before it
#   can be used
#
# Locally the same check is waived with -skipPackagePluginValidation, which
# Xcode Cloud does not pass. This is the equivalent for the CI machine.
# The key really is spelled "Validatation" by Xcode.
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
