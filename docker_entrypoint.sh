#!/bin/sh

set -ea

echo
echo "Starting Hello MariaDB..."
echo

# Setup MariaDB
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

# check if the 'mysql' system database exists
if [ -d /var/lib/mysql/mysql ]; then
    echo "[i] MariaDB directory already present, skipping creation"
    chown -R mysql:mysql /var/lib/mysql

    # get root password from passwords file, we'll need it later. The passwords file is created and updated on every run (and included in backups)
    export MYSQL_ROOT_PASSWORD=$(yq e '.root' /root/data/start9/passwords.yaml)
    export MYSQL_PASSWORD=$(yq e '.app' /root/data/start9/passwords.yaml)
else
    echo "[i] MariaDB data directory not found, creating initial DBs"

    mkdir -p /var/lib/mysql
    chown -R mysql:mysql /var/lib/mysql

    # install system db
    mysql_install_db --user=mysql --ldata=/var/lib/mysql >/dev/null

    # generate the root password
    if [ "$MYSQL_ROOT_PASSWORD" = "" ]; then
        export MYSQL_ROOT_PASSWORD=$(pwgen 16 1)
        # echo "[i] MariaDB root Password: $MYSQL_ROOT_PASSWORD"
    fi

    # create a database and give privileges for the 'app'
    MYSQL_DATABASE=${MYSQL_DATABASE:-"app"}
    MYSQL_USER=${MYSQL_USER:-"app"}
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-"app"}

    tfile=$(mktemp)
    if [ ! -f "$tfile" ]; then
        return 1
    fi

    cat <<EOF >$tfile
USE mysql;
FLUSH PRIVILEGES ;
GRANT ALL ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION ;
GRANT ALL ON *.* TO 'root'@'localhost' identified by '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION ;
SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
DROP DATABASE IF EXISTS test ;
FLUSH PRIVILEGES ;
EOF

    echo "[i] Creating database: $MYSQL_DATABASE"
    echo "[i] with character set: 'utf8' and collation: 'utf8_general_ci'"
    echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` CHARACTER SET utf8 COLLATE utf8_general_ci;" >>$tfile
    
    echo "[i] Creating user: $MYSQL_USER with password $MYSQL_PASSWORD"
    echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';" >>$tfile
    echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';" >>$tfile
    echo "FLUSH PRIVILEGES;" >>$tfile

    # run the script
    /usr/sbin/mysqld --user=mysql --datadir='/var/lib/mysql' --bootstrap --verbose=0 --skip-networking=0 <$tfile
    rm -f $tfile

    echo
    echo 'MariaDB init process done.'
    echo
fi

# Update stats (properties) file

mkdir -p /root/data/start9
cat <<EOF >/root/data/start9/stats.yaml
data:
  DbGate username:
    copyable: true
    description: Username for the DbGate User Interface.
    masked: false
    qr: false
    type: string
    value: root
  MariaDB root password:
    copyable: true
    description: Password for the DbGate User interface. This is also your MariaDB root password. Use it with caution!
    masked: true
    qr: false
    type: string
    value: $MYSQL_ROOT_PASSWORD
  MariaDB app password:
    copyable: true
    description: This is the MariaDB password for the 'app' user. Use it with caution!
    masked: true
    qr: false
    type: string
    value: $MYSQL_PASSWORD
version: 2
EOF

cat <<EOF >/root/data/start9/passwords.yaml
root: $MYSQL_ROOT_PASSWORD
app: $MYSQL_PASSWORD
EOF

# Run MariaDB

/usr/sbin/mysqld --user=mysql --datadir='/var/lib/mysql' --console --skip-networking=0 --bind-address=0.0.0.0 &
db_process=$!

# Loop until MariaDB is up
while ! mysql -h 127.0.0.1 -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; do
  echo "Waiting for MariaDB to be up..."
  sleep 1
done

echo "MariaDB is up!"

# Run DbGate

export NODE_ENV=production
export LOG_LEVEL=warn
export FILE_LOG_LEVEL=info
export CONSOLE_LOG_LEVEL=warn

#export CONNECTIONS=mariadb
export LABEL_mariadb=MariaDB
export SOCKET_PATH_mariadb=/run/mysqld/mysqld.sock
# we connect using a socket path, but could also use ip/port like this:
#export SERVER_mariadb=127.0.0.1
#export PORT_mariadb=3306
export USER_mariadb=root
export PASSWORD_mariadb=$MYSQL_ROOT_PASSWORD
export ENGINE_mariadb=mariadb@dbgate-plugin-mysql

export LOGINS=root
export LOGIN_PASSWORD_root=$MYSQL_ROOT_PASSWORD
export BASIC_AUTH=true

cd /home/dbgate-docker

node bundle.js --listen-api &
dbgate_process=$!

# run our demo 'App'

lighttpd -f /etc/lighttpd/lighttpd.conf &
app_process=$!

# hook the TERM signal and wait for all our processes

_term() {
    echo "Caught TERM signal!"
    kill -TERM "$app_process" 2>/dev/null
    kill -TERM "$dbgate_process" 2>/dev/null
    kill -TERM "$db_process" 2>/dev/null
}

trap _term TERM
wait $db_process $dbgate_process $app_process
