# CKAN Install Script

More or less automatic installation of CKAN on Red Hat-like Linux
distros. Tested on Fedora 22 and 23.

## Usage

1. Install dependencies

```
dnf install httpd httpd-devel mod_wsgi postgresql-server postgresql git redhat-rpm-config
dnf install python-devel python-pip libpqxx-devel python-pip python-virtualenv git-core

# Create a DB user, e.g.,
sudo -u postgres createuser -S -D -R -P "ckan_default"

```
2. Edit variables in `install_ckan.sh`
3. Run `$ ./install_ckan.sh`