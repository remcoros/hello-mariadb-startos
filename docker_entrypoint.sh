#!/bin/sh

set -ea

_term() {
    echo "Caught TERM signal!"
    kill -TERM "$app_process" 2>/dev/null
    kill -TERM "$dbgate_process" 2>/dev/null
    kill -TERM "$db_process" 2>/dev/null    
}

echo
echo "Starting Hello MariaDB..."
echo

# Setup MariaDB
if [ -d "/run/mysqld" ]; then
    echo "[i] mysqld already present, skipping creation"
    chown -R mysql:mysql /run/mysqld
else
    echo "[i] mysqld not found, creating...."
    mkdir -p /run/mysqld
    chown -R mysql:mysql /run/mysqld
fi

if [ -d /var/lib/mysql/mysql ]; then
    echo "[i] MariaDB directory already present, skipping creation"
    chown -R mysql:mysql /var/lib/mysql
else
    echo "[i] MariaDB data directory not found, creating initial DBs"

    mkdir -p /var/lib/mysql
    chown -R mysql:mysql /var/lib/mysql

    mysql_install_db --user=mysql --ldata=/var/lib/mysql >/dev/null

    if [ "$MYSQL_ROOT_PASSWORD" = "" ]; then
        MYSQL_ROOT_PASSWORD=`pwgen 16 1`
        echo "[i] MariaDB root Password: $MYSQL_ROOT_PASSWORD"
        export MYSQL_ROOT_PASSWORD
    fi

    MYSQL_DATABASE=${MYSQL_DATABASE:-"dbgate"}
	MYSQL_USER=${MYSQL_USER:-"dbgate"}
	MYSQL_PASSWORD=${MYSQL_PASSWORD:-"dbgate"}

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
    mkdir -p /root/data/start9
    cat <<EOF >/root/data/start9/stats.yaml
data:
  MariaDB root password:
    copyable: true
    description: Remember that you are always the one in control. This is your MariaDB root password. Use it with caution!
    masked: true
    qr: false
    type: string
    value: $MYSQL_ROOT_PASSWORD
version: 2
EOF

	if [ "$MYSQL_DATABASE" != "" ]; then
		echo "[i] Creating database: $MYSQL_DATABASE"
		echo "[i] with character set: 'utf8' and collation: 'utf8_general_ci'"
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` CHARACTER SET utf8 COLLATE utf8_general_ci;" >> $tfile

        if [ "$MYSQL_USER" != "" ]; then
            echo "[i] Creating user: $MYSQL_USER with password $MYSQL_PASSWORD"
            echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';" >> $tfile
            echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';" >> $tfile
            echo "FLUSH PRIVILEGES;" >> $tfile
	    fi
	fi

    /usr/sbin/mysqld --user=mysql --datadir='/var/lib/mysql' --bootstrap --verbose=0 --skip-networking=0 <$tfile
    rm -f $tfile

    echo
    echo 'MariaDB init process done.'
    echo
fi

# Run MariaDB
/usr/sbin/mysqld --user=mysql --datadir='/var/lib/mysql' --console --skip-networking=0 --bind-address=0.0.0.0 &
db_process=$!

# Run DbGate

export CONNECTIONS=mariadb
export LABEL_mariadb=MariaDB
export SERVER_mariadb=127.0.0.1
export USER_mariadb=root
export PASSWORD_mariadb=$(yq e '.data.["MariaDB root password"].value' /root/data/start9/stats.yaml)
export PORT_mariadb=3306
export ENGINE_mariadb=mysql@dbgate-plugin-mysql

cd /home/dbgate-docker 

node bundle.js --listen-api &
dbgate_process=$!

# run our demo App

lighttpd -f /etc/lighttpd/lighttpd.conf &
app_process=$!

trap _term TERM
wait $db_process $dbgate_process $app_process
