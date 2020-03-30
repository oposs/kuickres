#!/bin/sh
 
set -e
V=$(cat VERSION)
echo $V `date +"%Y-%m-%d %H:%M:%S %z"` `git config user.name` '<'`git config user.email`'>' >> CHANGES.new
echo >> CHANGES.new
echo ' -' >> CHANGES.new
echo >> CHANGES.new
cat CHANGES >> CHANGES.new && mv CHANGES.new CHANGES
$EDITOR CHANGES
./bootstrap
make test
make dist
scp *-$V.tar.gz freddie:scratch
ssh freddie 'set -x ;kill $(cat opt/kuickres/kuickres.pid);cd scratch; tar xf kuickres-'$V'.tar.gz; cd kuickres-'$V'; make install;cd ~/opt/kuickres;(./bin/kuickres.pl prefork --listen http://*:38433 --pid-file=kuickres.pid </dev/null 2>&1 >kuickres.log &)'
