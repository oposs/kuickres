#!/bin/sh
export MOJO_MODE=development
export MOJO_LOG_LEVEL=debug
exec `dirname $0`/kuickres.pl prefork --listen 'http://*:3626'
