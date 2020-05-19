#!/usr/bin/env perl
BEGIN {
    unlink glob "/tmp/kuickres-testing*";
}

use FindBin;
use lib $FindBin::Bin.'/../thirdparty/lib/perl5';
use lib $FindBin::Bin.'/../lib';
use Mojo::Base -base;
use Crypt::ScryptKDF qw(scrypt_hash scrypt_hash_verify);
use Time::Piece;
use Test::More;
use Test::Mojo;
use POSIX qw(strftime);
use Mojo::Util qw(hmac_sha1_sum dumper);

use_ok 'Kuickres';

$ENV{Kuickres_CONFIG} = $FindBin::RealBin."/kuickres.yaml";
unlink glob('/tmp/kuickres-testing.*');
my $PIN = int(rand()*1e7);

my $t = Test::Mojo->new('Kuickres');
my $user = 'user@dummy';
my $pass = 'access'.rand();
my $db =  $t->app->database->sql->db;
my $userId = $db->insert('cbuser',{
    cbuser_login => $user,
    cbuser_password => hmac_sha1_sum($pass),
    cbuser_pin => $PIN,
})->last_insert_id;
$db->insert('cbuserright',{
    cbuserright_cbuser => $userId,
    cbuserright_cbright => $_
}) for 1..2;

my $id = 44;

$t->post_ok('/QX-JSON-RPC', json => {
    id => ++$id,
    service => 'default',
    method => 'login',
    params => [$user,$pass]
})
  ->status_is(200)
  ->content_type_is('application/json; charset=utf-8')
  ->json_is('/id' => $id)
  ->json_has('/result/sessionCookie');

my $cookie = { 'X-Session-Cookie' => $t->tx->res->json->{result}{sessionCookie} };
my $key;
my %metaInfo;

subtest "Data Entry" => sub {
    my $startTime = time- (time % 24*3600) + 30*3600;
    for my $data (
        [ AgegroupAddForm => {  agegroup_name => "sadfu" } ],
        [ DistrictAddForm => {  district_name => "Bern" } ],
        [ LocationAddForm => {  
            location_address => "BlaBla 2\n388383",
            location_open_yaml => <<YAML_END,
- type: open
  day: ['mon','tue','wed','thu','fri','sat','sun']
  time:
    from: 2:00
    to: 23:00
YAML_END
            location_name => "Rufi"
        } ],
        [ RoomAddForm => {
            room_name => "Hinterzimmer"
        }],
        [ BookingAddForm => {}],
        [ BookingAddForm => {}],
        [ BookingAddForm => {}],
    ){
        note $data->[0];
        if ( $data->[0] eq 'RoomAddForm') {
            $data->[1]{room_location} = $metaInfo{LocationAddForm}[0]{recId}
        }
        if ( $data->[0] eq 'BookingAddForm') {
            $data->[1] = {
                booking_agegroup => $metaInfo{AgegroupAddForm}[0]{recId},
                booking_cbuser => 1,
                booking_comment => "Hello",
                booking_district => $metaInfo{DistrictAddForm}[0]{recId},
                booking_room => $metaInfo{RoomAddForm}[0]{recId},
                booking_school => "test school",
                booking_mobile => '+41 222',
                booking_date => $startTime,
                booking_from => strftime("%H:%M",localtime($startTime)),
                booking_to => strftime("%H:%M",localtime($startTime+300))
            };
            $startTime += 3600;
        }
        $t->app->mailTransport->clear_deliveries;
        
        $t->post_ok('/QX-JSON-RPC', qxCall(
            processPluginData => []
        ))
        ->status_is(200)
        ->json_is('/error/code',39943,'Access Test');

        $t->post_ok('/QX-JSON-RPC',$cookie, qxCall(
            processPluginData => [
                $data->[0] => {
                    key =>"save",
                    formData => $data->[1]
                },
                {
                    qxLocale =>"de"
                }
            ]
        ))
        ->status_is(200)
        ->json_is('/result/action' => 'dataSaved');
        push @{$metaInfo{$data->[0]}}, $t->tx->res->json->{result}{metaInfo};
        if ( $data->[0] eq 'BookingAddForm') {
            my $delivery = $t->app->mailTransport->shift_deliveries;
            # diag $delivery->{email}->as_string;
            is $delivery->{successes}[0], $user, "mail recipient check";
            like $delivery->{email}->as_string, qr{Rufi};
        }
    }
    done_testing();
};

subtest 'REST API' => sub {
    $t->get_ok('/REST/v1.html')
    ->status_is(200)
    ->content_like(qr{signage});
    my $lId = $metaInfo{LocationAddForm}[0]{recId};
    $t->get_ok('/REST/v1/doorKeys/'.$lId)
    ->status_is(401)
    ->json_is('/errors/0/message',"X-Api-Key header not present");
    
    my $header = { 'X-Api-Key' => 'access'};

    $t->get_ok('/REST/v1/doorKeys/'.$lId,$header)
    ->status_is(200)
    ->json_is('/1/bookingId',2);

    my $doorKeys = $t->tx->res->json;

    is scrypt_hash_verify($PIN,$doorKeys->[0]{pinHash}),1,'door pin check';

    $t->post_ok('/REST/v1/reportKeyUse',$header, json => [ {
        entryTs => time,
        bookingId => $doorKeys->[0]{bookingId},
        hash => scrypt_hash($doorKeys->[0]{bookingId}.":".$PIN)
    }])
    ->status_is(201)
    ->content_is('');
    
    $t->get_ok('/REST/v1/signage/'.$lId)
    ->status_is(200)
    ->content_like(qr{Rufi});
    
    done_testing();
};

done_testing();


sub qxCall {
    my $method = shift;
    my $params = shift;
    state $id = 33;
    return json => {
        "service"=>"default",
        "method"=>$method,
        "id"=>++$id,
        "params"=>$params
    }
}
