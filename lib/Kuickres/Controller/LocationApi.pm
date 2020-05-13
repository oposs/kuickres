package Kuickres::Controller::LocationApi;
use Crypt::ScryptKDF qw(scrypt_hash scrypt_hash_verify);

use Mojo::Base 'Mojolicious::Controller',-signatures;
use Mojo::Util qw(dumper camelize);
sub db ($c) {
    $c->app->database->sql->db;
}

sub get_door_keys {
    my $c = shift->openapi->valid_input or return;
    my $locationId = $c->param('locationId');
    my $res = $c->db->query(<<SQL_END,time,time+3*24*3600,$locationId)->hashes;
    SELECT booking_id AS "booking_id",
           booking_start_ts AS "valid_from_ts",
           booking_start_ts + booking_duration_s AS "valid_until_ts",
           cbuser_pin
    FROM booking
    JOIN cbuser ON booking_cbuser = cbuser_id
    JOIN room ON booking_room = room_id
    WHERE booking_start_ts + booking_duration_s > CAST(? AS INTEGER)
        AND booking_start_ts < CAST(? AS INTEGER)
        AND room_location = CAST(? AS INTEGER)
SQL_END
    for my $row (@$res){
        # keep the hash stable so that the satellite can see if there is a change
        $row->{pin_hash} = scrypt_hash(delete $row->{cbuser_pin},$row->{valid_from_ts});
        for my $key (keys %$row) {
            $row->{lcfirst(camelize($key))} = delete $row->{$key};
        }
    }
    #warn dumper $res;
    return $c->render(openapi => $res);
}

sub report_key_use {
    my $c = shift->openapi->valid_input or return;
    my $array = $c->req->json;
    for my $entry (@$array) {
        my $bk = $c->db->query(<<SQL_END,$entry->{bookingId})->hash;
    SELECT * FROM booking 
        JOIN room ON booking_room = room_id
        JOIN cbuser ON booking_cbuser = cbuser_id        
        WHERE booking_id = ?
SQL_END
        if (not $bk){
            $c->log->error("invalid bookingId from ".$c->tx->remote_address);
            return $c->render(code => 404, openapi => { status => 404, errors => [
                {
                    message => 'unknown booking',
                }
            ]});
        }
        if (not scrypt_hash_verify("$bk->{booking_id}:$bk->{cbuser_pin}",$entry->{hash})){
            $c->log->error("invalid hash from ".$c->tx->remote_address);
            return $c->render(code => 404, openapi => { status => 404, errors => [
                {
                    message => 'invalid hash',
                }
            ]});
        }                                            
        eval {
            $c->db->insert("access_log",{
                access_log_entry_ts => $entry->{entryTs},
                access_log_insert_ts => time,
                access_log_location => $bk->{room_location},
                access_log_ip => $c->tx->remote_address,
                access_log_cbuser => $bk->{booking_cbuser},
                access_log_booking => $entry->{bookingId},
            });
        };
        if ($@){
            $c->log->error($@);
            return $c->render(status => 500, openapi=>{status => 500,
                errors => [{
                    message => "Failed to update access log"
                }]
            });
        }
    }
    return $c->render(status=>201,text=>'');
}

sub get_signage {
    my $c = shift->openapi->valid_input or return;
    my $lid = $c->param('locationId');
    my $res = $c->db->query(<<SQL_END,time,time+2*24*3600,$lid)->hashes;
    SELECT booking.*,cbuser_login,cbuser_family,cbuser_given,room.*,location.* FROM booking
    JOIN cbuser ON booking_cbuser = cbuser_id
    JOIN room ON booking_room = room_id
    JOIN location ON room_location = location_id
    WHERE booking_start_ts > CAST(? AS INTEGER)
        AND booking_start_ts < CAST(? AS INTEGER)
        AND room_location = CAST(? AS INTEGER)
    ORDER BY booking_start_ts
SQL_END
    # warn dumper $res;
    $c->stash(bookings=>$res);
    $c->render;
}

1;