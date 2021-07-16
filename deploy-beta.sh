#!/bin/sh
set -e
V=$(cat VERSION)
echo $V $(date +"%Y-%m-%d %H:%M:%S %z") $(git config user.name) '<'$(git config user.email)'>' >> CHANGES.new
echo >> CHANGES.new
echo ' -' >> CHANGES.new
echo >> CHANGES.new
cat CHANGES >> CHANGES.new && mv CHANGES.new CHANGES
$EDITOR CHANGES
./bootstrap
make dist
cat kuickres-$V.tar.gz | ssh kuicksa@freddie 'tar zxf -;cd kuickres-'$V';./configure --prefix=$HOME/opt/kuickres-beta;make install;$HOME/start-beta.sh'