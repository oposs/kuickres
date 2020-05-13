#!/usr/bin/env perl
use FindBin;
use lib $FindBin::Bin.'/../thirdparty/lib/perl5';
use lib $FindBin::Bin.'/../lib';


use Test::More;
use Test::Mojo;

use_ok 'Kuickres';

my $t = Test::Mojo->new('Kuickres');

$t->post_ok('/QX-JSON-RPC','{"id":1,"service": "default", "method":"ping"}')
  ->status_is(200)
  ->content_type_is('application/json; charset=utf-8')
  ->json_is({id => 1,result => "pong"});

done_testing();
