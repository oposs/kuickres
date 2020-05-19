#!/usr/bin/env perl
use FindBin;
use lib $FindBin::Bin.'/../thirdparty/lib/perl5';
use lib $FindBin::Bin.'/../lib';
use Mojo::Base -base;
use Test::More;

use_ok 'Kuickres::Model::OperatingHours';
eval {
    Kuickres::Model::OperatingHours->new([{
        type => 'open',
        day => [qw(montag)],
        time => {
            from => '10:00',
            to => '14:00',
        } 
    }]);
};    
my $ex = $@;
is (ref $ex, 'Mojo::Exception','exception class');
like ($ex, qr/Not in enum list: mon,/,'exception content');
my $oh = Kuickres::Model::OperatingHours->new([
{
    type => 'close',
    day => [qw(mon)],
    time => {
        from => '12:00',
        to => '13:00',
    } 
},
{
    type => 'open',
    day => [qw(mon fri)],
    time => {
        from => '10:00',
        to => '14:00',
    } 
},
]);
ok $oh->isItOpen('15.5.2020 12:00','15.5.2020 14:00'),'check open';
ok !$oh->isItOpen('11.5.2020 12:59','11.5.2020 14:00'),'check closed';
ok !$oh->isItOpen('11.5.2020 11:00','11.5.2020 13:00'),'check overlap';
ok !$oh->isItOpen('12.5.2020 12:59','12.5.2020 14:00'),'undefined';

done_testing();