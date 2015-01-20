# NAME

itemcount - GBV PICA+ item counter

[![Build Status](https://travis-ci.org/gbv/itemcount.svg)](https://travis-ci.org/gbv/itemcount)

# SYNOPSIS

The application is automatically started as service, listening on port 6023.

    sudo service itemcount {status|start|stop|restart}

# INSTALLATION

The application is packaged as Debian package and installed at
`/srv/itemcount/`. Log files are located at `/var/log/itemcount/`.

# CONFIGURATION

See `/etc/default/itemcount`. Restart is needed after changes.

# SEE ALSO

* Source code at <https://github.com/gbv/itemcount>

