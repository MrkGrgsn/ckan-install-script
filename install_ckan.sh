#!/bin/bash

# Assumptions:
# - System is CentOS7/RHEL7/Fedora whatever (tested on Fedora 22)
# - System packages are installed
# - "ckan_default" postgresql user already exists
# - solr is installed and running at http://127.0.0.1:8983/solr
# - script is run with root permissions

SITE_ID="25"
ROOT_PATH="/"

# Tag/branch of CKAN to use, e.g., master or ckan-2.3.4
CKAN_VERSION="ckan-2.5.2"
CKAN_REPO="https://github.com/ckan/ckan.git"
#CKAN_REPO="https://git.links.com.au/clients/link-ckan.git"

USER="mgregson"
GROUP="apache"

DB_USER="ckan_default"
DB_PASS="pass"

SOLR_SERVER_DIR="/var/solr/data"
SOLR_INSTALL_DIR="/opt/solr"

venv_dir="/usr/lib/ckan/$SITE_ID"

# directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

mkdir -p "$venv_dir"
chown "$USER.$GROUP" "$venv_dir"
chmod -R g+ws "$venv_dir"

virtualenv "$venv_dir"

cd "$venv_dir"
. "$venv_dir/bin/activate"

# Upgrade pip because it's upgrade warnings are annoying and the
# system one is usually out-of-date
pip install --upgrade pip

# Install CKAN
echo "Installing CKAN ..."
pip install -e "git+$CKAN_REPO@$CKAN_VERSION#egg=ckan"
pip install -r "$venv_dir/src/ckan/requirements.txt"

# Re-activate virtual env
deactivate
. "$venv_dir/bin/activate"

echo "Creating PostgreSQL DB ... "

# Assumes ckan_default user exists already
sudo -u postgres createdb -O ckan_default "ckan_$SITE_ID" -E utf-8

# Config

echo "Creating CKAN config ..."

config_dir="/etc/ckan/$SITE_ID"
mkdir -p "$config_dir"
chown "$USER.$GROUP" "$config_dir"
chmod -R g+s "$config_dir"

config_file="$config_dir/development.ini"
paster make-config ckan "$config_file"

# Setup solr core - assumes solr is already installed at SOLR_DIR

echo "Setting up solr core"

cp -r "$SOLR_INSTALL_DIR/server/solr/configsets/basic_configs/conf" "$config_dir/solr"
cp -f "$DIR/solrconfig.xml" "$config_dir/solr"
ln -snf "$venv_dir/src/ckan/ckan/config/solr/schema.xml" "$config_dir/solr/schema.xml"
chown -R solr.solr "$config_dir/solr"

core_dir="$SOLR_SERVER_DIR/$SITE_ID"
mkdir -p "$core_dir/data"
chown -R solr.solr "$core_dir"
ln -snf "$config_dir/solr" "$core_dir/conf"
chown -R solr.solr "$config_dir/solr"

service solr restart

# Update CKAN config file

echo "Updating config file ..."

sed -i -- "s|ckan\.site_url\s*=.*$|ckan.site_url = http://$SITE_ID.dev|g" "$config_file"
sed -i -- "s|ckan\.site_id\s*=.*$|ckan.site_id = $SITE_ID|g" "$config_file"
sed -i -- "s|#solr_url.*$|solr_url = http://127.0.0.1:8983/solr/$SITE_ID|g" "$config_file"
sed -i -- "s|sqlalchemy\.url\s*=.*$|sqlalchemy.url = postgresql://$DB_USER:$DB_PASS@localhost/ckan_$SITE_ID|g" "$config_file"

# TODO: set ckan.root_path in ini file

echo "Linking who.ini ..."
ln -snf "$venv_dir/src/ckan/ckan/config/who.ini" "$config_dir/who.ini"

echo "Setting up httpd ..."

cp -f "$DIR/apache.wsgi" "$config_dir/"
sed -i -- "s|{{SITE_ID}}|$SITE_ID|g" "$config_dir/apache.wsgi"

cp -f "$DIR/httpd.conf" "/etc/httpd/conf.d/ckan_$SITE_ID.conf"
sed -i -- "s|{{SITE_ID}}|$SITE_ID|g" "/etc/httpd/conf.d/ckan_$SITE_ID.conf"
sed -i -- "s|{{ROOT_PATH}}|$ROOT_PATH|g" "/etc/httpd/conf.d/ckan_$SITE_ID.conf"

echo "127.0.0.1 $SITE_ID.dev www.$SITE_ID.dev" >> /etc/hosts

systemctl restart httpd

echo "Setting up storage ..."
storage_path="$venv_dir/storage"
mkdir -p "$storage_path"
chmod g+w "$storage_path"
sed -i -- "s|#ckan\.storage_path.*$|ckan.storage_path = $storage_path|g" "$config_file"

# CKAN DB init

cd "$venv_dir/src/ckan"
paster db init -c "$config_file"

# Fix permissions
chown -R "$USER.$GROUP" "$venv_dir"
chmod -R g+ws "$venv_dir"

# cleanup
deactivate

echo
echo
echo "Done!"
echo
echo "CKAN is in $venv_dir"
echo "CKAN and SOLR config is in $config_dir"
echo "SOLR core is in $core_dir"
echo
echo "-----------------------------------"
echo
echo "You need to manually add the solr core at http://127.0.0.1:8983/solr/#/~cores (FIXME)"
echo
echo "-----------------------------------"
echo
echo "Run CKAN by doing:"
echo "$ cd $venv_dir/src/ckan"
echo "$ paster serve $config_file"
