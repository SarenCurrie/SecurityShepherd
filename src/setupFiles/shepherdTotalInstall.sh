#!/bin/bash

set -e

shepherdServerXmlLocation=https://raw.githubusercontent.com/owasp/SecurityShepherd/master/SecurityShepherdCore/setupFiles/tomcatShepherdSampleServer.xml
shepherdWebXmlLocation=https://raw.githubusercontent.com/owasp/SecurityShepherd/master/SecurityShepherdCore/setupFiles/tomcatShepherdSampleWeb.xml
shepherdManualPackLocation=https://github.com/OWASP/SecurityShepherd/releases/download/v3.0/owaspSecurityShepherd_V3.0.Manual.Pack.zip
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
else
  # Install Pre-Requisite Stuff
  sudo apt-get update -y
  sudo apt-get install -y mysql-server-5.7
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:webupd8team/java
  sudo apt-get update -y
  sudo apt-get install -y oracle-java8-installer
  sudo apt-get install -y tomcat8 tomcat8-admin
  sudo apt-get install -y unzip

  #Download and Deploy Shepherd to Tomcat and MySQL
  sudo wget --quiet $shepherdManualPackLocation -O manualPack.zip
  mkdir -p manualPack
  unzip manualPack.zip -d manualPack
  cd ~
  sudo apt-get install -y dos2unix
  dos2unix manualPack/*.sql
  dos2unix manualPack/*.js
  sudo chmod 775 manualPack/*.war
  cd /var/lib/tomcat8/webapps/
  sudo rm -rf *
  sudo mv -v ~/manualPack/ROOT.war ./
  cd ~/manualPack/
  echo "Configuring MySQL"
  echo "Please enter MySQL Password (on Ubuntu 18.04, leave this blank):"
  sudo mysql -u root -e "source coreSchema.sql" --force -p
  echo "Please enter MySQL Password (on Ubuntu 18.04, leave this blank):"
  sudo mysql -u root -e "source moduleSchemas.sql" --force -p

  #Install and Config MongoDB
  echo "Installing MongoDB"
  sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5
  echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.6 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.6.list
  sudo apt-get update
  sudo apt-get install -y mongodb-org=3.6.7 mongodb-org-server=3.6.7 mongodb-org-shell=3.6.7 mongodb-org-mongos=3.6.7 mongodb-org-tools=3.6.7
  sudo systemctl enable mongod
  sleep 10
  mongo /home/*/manualPack/mongoSchema.js

  #Configuring Tomcat to Run the way we want (Oracle Java, HTTPs, Port 80 redirect to 443
  echo "Configuring Tomcat"
  echo "JAVA_HOME=/usr/lib/jvm/java-8-oracle" | sudo tee -a /etc/default/tomcat8
  echo "AUTHBIND=yes" | sudo tee -a /etc/default/tomcat8
  cd ~
  homeDirectory="$(pwd)/"
  keyStoreFileName="shepherdKeystore.jks"
  echo "Please enter the password you would like to use for your Keystore (Used for HTTPs on Tomcat)"
  keytool -genkey -alias tomcat -keyalg RSA -destkeystore $keyStoreFileName -deststoretype pkcs12
  wget --quiet $shepherdWebXmlLocation -O web.xml
  wget --quiet $shepherdServerXmlLocation -O server.xml
  escapedFileName=$(echo "$homeDirectory$keyStoreFileName" | sed 's/\//\\\//g')
  sed -i "s/____.*____/$escapedFileName/g" server.xml
  read -s -p "Please Enter the Keystore Password you used earlier and press [ENTER]" keystorePassword
  echo ""
  sed -i "s/___.*___/$keystorePassword/g" server.xml
  echo "Overwriting default tomcat Config with new config... (Do Not Ignore Any Errors From this point)"
  sudo mv server.xml /var/lib/tomcat8/conf/server.xml
  sudo mv web.xml /var/lib/tomcat8/conf/web.xml
  sudo touch /etc/authbind/byport/80
  sudo touch /etc/authbind/byport/443
  sudo chmod 500 /etc/authbind/byport/80
  sudo chmod 500 /etc/authbind/byport/443
  sudo chown tomcat8 /etc/authbind/byport/80
  sudo chown tomcat8 /etc/authbind/byport/443

  #Restart Tomcat
  sudo service tomcat8 restart
  echo "Shepherd is Ready to Rock!"
fi
