# The target file is run before *every* Origen operation and is used to instantiate
# the runtime environment - usually this means instantiating a top-level SoC or
# IP model.
#
# Naming is arbitrary but instances names should be prefixed with $ which indicates a
# global variable in Ruby, and this is required in order for the objects instantiated
# here to be visible throughout your application code.

$jira = Jironimo.launch  # Instantiate a JIRA client
