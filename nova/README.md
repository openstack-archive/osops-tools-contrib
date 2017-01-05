# Nova folder

this folder contains scripts that are related to Nova

## Compare Nova state to hypervisor state: `nova-libvirt-compare.py`

This retrieves all instances in a region (or all regions when called
with `-a`), then compares that with the libvirt domains running on all
hypervisor hosts in that region, and reports any differences.

### Usage

    usage: nova-libvirt-compare.py [-h] [-a] [-l REMOTE_USER]
                                   [--no-note-incomplete]
                                   [--blindly-trust-host-keys] [-p PROCESSES] [-v]

    Check for inconsistent state between Nova DB and hypervisors

    optional arguments:
      -h, --help            show this help message and exit
      -a, --all-regions     query all regions
      -l REMOTE_USER, --remote-user REMOTE_USER
                            SSH remote username for connecting to hypervisors
      --no-note-incomplete  Don't report incomplete instances
      --blindly-trust-host-keys
                            Accept all SSH host keys. This enables man-in-the-
                            middle attacks!
      -p PROCESSES, --processes PROCESSES
                            Number of parallel processes connecting to hypervisors
      -v, --verbose         verbose

### Example

    $ ./nova-libvirt-compare.py
    Hypervisor zhdk0062.zhdk.cloud.switch.ch should know about bd384f32-5e05-43a5-a66e-fc11693a733b, but doesn't
    Instance ebd1c623-35c3-4385-998f-10a96ecfbcdf (state BUILD) has no hypervisor
