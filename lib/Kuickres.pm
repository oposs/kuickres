package Kuickres;

use Mojo::Base 'CallBackery', -signatures;
use CallBackery::Model::ConfigJsonSchema;
use Mojo::Util qw(dumper);
use Digest::SHA;
use SQL::Abstract::Pg;
use Carp;

=head1 NAME

Kuickres - the application class

=head1 SYNOPSIS

 use Mojolicious::Commands;
 Mojolicious::Commands->start_app('Kuickres');

=head1 DESCRIPTION

Configure the mojolicious engine to run our application logic

=cut

=head1 ATTRIBUTES

Kuickres has all the attributes of L<CallBackery> plus:

=cut

=head2 config

use our own plugin directory and our own configuration file:

=cut

has config => sub ($self) {
    my $config = CallBackery::Model::ConfigJsonSchema->new(
        app => $self,
        file => $ENV{Kuickres_CONFIG} || $self->home->rel_file('etc/kuickres.yaml')
    );
    my $s = $config->schema->{properties}{BACKEND};
    $s->{properties}{api_key} = {
        type => 'string'
    };
    $s->{properties}{smtp_url} = {
        type => 'string'
    };
    $s->{properties}{bcc} = {
        type => 'string'
    };
    $s->{properties}{from} = {
        type => 'string'
    };
    push @{$s->{required}},'api_key','from';

    unshift @{$config->pluginPath}, __PACKAGE__.'::GuiPlugin';
    return $config;
};


has database => sub ($self) {
    my $database = $self->SUPER::database();
    $database->sql->options->{sqlite_see_if_its_a_number}=1;
    $database->sql->migrations
        ->name('KuickresBaseDB')
        ->from_data(__PACKAGE__,'appdb.sql')
        ->migrate;

    return $database;
};

has mailTransport => sub ($self) {
    if ($ENV{HARNESS_ACTIVE}) {
        require Email::Sender::Transport::Test;
        return Email::Sender::Transport::Test->new
    }
    return;
};

sub startup ($self) {
    my $apiKey = $self->config->cfgHash->{BACKEND}{api_key};
    $self->database; # make sure to migrate at start time
    $self->plugin("OpenAPI" => {
        spec => $self->home->child('share', 'openapi.yaml'),
        schema => 'v3',
        render_specification => 1,
        render_specification_for_paths => 1,
        security => {
            apiKeyHeader => sub ($c, $definition, $scopes, $cb) {
                if (my $key = 
                    $c->tx->req->content->headers->header('X-API-Key')) {
                    my $keyHash = Digest::SHA::hmac_sha1_hex($key);
                    if ($keyHash eq $apiKey) {
                        return $c->$cb();
                    }
                    return $c->$cb('Api Key not valid');
                }
                return $c->$cb('X-Api-Key header not present');
            }
        }
    });
    return $self->SUPER::startup();
}
1;

=head1 COPYRIGHT

Copyright (c) 2020 by Tobias Oetiker. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut

__DATA__

@@ openapi.yaml @@



@@ appdb.sql

-- 1 up

CREATE TABLE location (
    location_id   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    location_name TEXT NOT NULL,
    location_open_yaml TEXT NOT NULL,
    location_address TEXT NOT NULL
);

INSERT INTO location (location_name,location_open_yaml,location_address)
    VALUES ('Sportzentrum Josef',
'- type: open
  day: ["mon","tue","wed","thu","fri"]
  time: { from: 8:00, to: 16:00 }
','Josefstrasse 219, 8005 Zürich');

CREATE TABLE room (
    room_id  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    room_location INTEGER NOT NULL REFERENCES location(location_id),
    room_name TEXT NOT NULL
);
INSERT INTO room (room_location,room_name)
    VALUES (1,'Sportzentrum Josef');


CREATE TABLE booking (
    booking_id  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    booking_cbuser INTEGER NOT NULL REFERENCES cbuser(cbuser_id),
    booking_room INTEGER NOT NULL REFERENCES room(room_id),
    booking_start_ts TIMESTAMP NOT NULL,
    booking_duration_s INTEGER NOT NULL
        CHECK( booking_duration_s > 0 ),
    booking_mobile TEXT NOT NULL,
    booking_school TEXT NOT NULL,
    booking_district INTEGER NOT NULL REFERENCES district(district_id),
    booking_agegroup INTEGER NOT NULL REFERENCES agegroup(agegroup_id),
    booking_create_ts TIMESTAMP NOT NULL,
    booking_delete_ts TIMESTAMP,
        CHECK( booking_delete_ts IS NULL 
            OR booking_delete_ts > booking_create_ts)
);

CREATE TABLE access_log (
    access_log_id  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    access_log_entry_ts TIMESTAMP NOT NULL,
    access_log_insert_ts TIMESTAMP NOT NULL,
    access_log_ip TEXT NOT NULL,
    access_log_location INTEGER REFERENCES location(location_id),
    access_log_cbuser INTEGER REFERENCES cbuser(cbuser_id),
    access_log_booking INTEGER REFERENCES booking(booking_id)
);

CREATE TABLE district (
    district_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    district_name TEXT NOT NULL
);

INSERT INTO district ('district_name')
VALUES ('Glattal'),('Letzi'),('Limmattal'),
    ('Schwamendingen'),('Uto'),('Waidberg'),('Zürichberg');

CREATE TABLE agegroup (
    agegroup_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    agegroup_name TEXT NOT NULL
);

INSERT INTO agegroup ('agegroup_name')
    VALUES ('Hort'),('Betreuung'),('4. Prim.'),('5. Prim.'),('6. Prim.'),('1. Sek'),('2. Sek'),('3. Sek'),('10. SJ'),('Andere');

DROP TABLE cbuser;
CREATE TABLE IF NOT EXISTS cbuser (
    cbuser_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    cbuser_login TEXT UNIQUE,
    cbuser_family TEXT,
    cbuser_given TEXT,
    cbuser_password TEXT NOT NULL,
    cbuser_note TEXT,
    cbuser_calendar_tag TEXT,
    cbuser_pin INTEGER 
        DEFAULT (substr(random() || '0000000',3,7))
);

-- add an extra right for people who can edit

INSERT INTO cbright (cbright_key,cbright_label)
    VALUES 
        ('booker','Booker');

-- 2 up

DELETE FROM agegroup WHERE agegroup_name = 'Betreuung';
UPDATE agegroup SET agegroup_name = 'Hort/Betreuung' WHERE agegroup_name = 'Hort';

-- 3 up

CREATE TABLE equipment (
    equipment_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    equipment_room INTEGER NOT NULL REFERENCES room(room_id),
    equipment_name TEXT NOT NULL,
    equipment_start_ts TIMESTAMP NOT NULL,
    equipment_end_ts TIMESTAMP,
    equipment_key TEXT NOT NULL UNIQUE 
        CHECK(regexp('^[-_0-9a-z]+$',equipment_key)),
    equipment_cost INTEGER NOT NULL DEFAULT 1
);

INSERT INTO equipment (equipment_room,
    equipment_name,equipment_start_ts,equipment_key)
    VALUES 
        (1,'Test A',100000,'test_a');

CREATE TABLE mbooking (
    mbooking_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    mbooking_cbuser INTEGER NOT NULL REFERENCES cbuser(cbuser_id),
    mbooking_room INTERGER NOT NULL REFERENCES room(room_id),
    mbooking_start_ts INTERGER NOT NULL,
    mbooking_end_ts INTEGER NOT NULL,
    mbooking_rule_json TEXT NOT NULL
        CHECK(json_valid(mbooking_rule_json)),
    mbooking_note TEXT,
    mbooking_create_ts TIMESTAMP NOT NULL,
    mbooking_delete_ts TIMESTAMP,
        CHECK( mbooking_delete_ts IS NULL 
            OR mbooking_delete_ts > mbooking_create_ts)
);

ALTER TABLE booking ADD booking_mbooking INTEGER
    REFERENCES mbooking(mbooking_id);

ALTER TABLE room ADD room_key 
    TEXT 
    CHECK(regexp('^[-_0-9a-z]+$',room_key));

CREATE UNIQUE INDEX room_key_idx ON room (room_key);

UPDATE room SET room_key = 'joseph' WHERE room_id = 1;

ALTER TABLE booking ADD booking_equipment_json 
    TEXT
    DEFAULT '[0]'
    NOT NULL
    CHECK(json_valid(booking_equipment_json));

CREATE TABLE usercat (
    usercat_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    usercat_name TEXT NOT NULL,
    usercat_rule_json TEXT NOT NULL CHECK(json_valid(usercat_rule_json))
);

INSERT INTO usercat (usercat_name,usercat_rule_json)
    VALUES 
        ('Plain','{"futureBookingDays": 60,"maxEquipmentPointsPerBooking": 3,"maxBookingHoursPerDay": 4,"equipmentList":["test_a"]}');

COMMIT;
PRAGMA foreign_keys=off;
BEGIN;

ALTER TABLE cbuser ADD cbuser_usercat INTEGER NOT NULL DEFAULT 1;

CREATE TABLE cbuser_new (
    cbuser_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    cbuser_login TEXT UNIQUE,
    cbuser_family TEXT,
    cbuser_given TEXT,
    cbuser_password TEXT NOT NULL,
    cbuser_note TEXT,
    cbuser_calendar_tag TEXT,
    cbuser_pin INTEGER DEFAULT (substr(random() || '0000000',3,7)),
    cbuser_usercat INTEGER NOT NULL default 1 REFERENCES usercat(usercat_id)
);

INSERT INTO cbuser_new SELECT * from cbuser;
DROP TABLE cbuser;
ALTER TABLE cbuser_new RENAME to cbuser;
COMMIT;
PRAGMA foreign_keys=on;
BEGIN;

