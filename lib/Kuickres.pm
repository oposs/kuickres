package Kuickres;

use Mojo::Base 'CallBackery', -signatures;
use CallBackery::Model::ConfigJsonSchema;
use Mojo::Util qw(dumper);
use Digest::SHA;

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
    push @{$s->{required}},'api_key';

    unshift @{$config->pluginPath}, __PACKAGE__.'::GuiPlugin';
    return $config;
};


has database => sub ($self) {
    my $database = $self->SUPER::database();
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
                    warn $apiKey;
                    return $c->$cb('Api Key not valid');
                }
                return $c->$cb('X-Api-Key header not present');
            }
        }
    });
    $self->SUPER::startup();
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
    location_open_start INTEGER NOT NULL,
    location_open_duration INTEGER NOT NULL,
    location_address TEXT NOT NULL
);

CREATE TABLE room (
    room_id  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    room_location INTEGER NOT NULL REFERENCES location(location_id),
    room_name TEXT NOT NULL
);

CREATE TABLE booking (
    booking_id  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    booking_cbuser INTEGER NOT NULL REFERENCES cbuser(cbuser_id),
    booking_room INTEGER NOT NULL REFERENCES room(room_id),
    booking_start_ts TIMESTAMP NOT NULL,
    booking_duration_s INTEGER NOT NULL
        CHECK( booking_duration_s > 0 ),
    booking_calendar_tag TEXT,
    booking_district INTEGER NOT NULL REFERENCES district(district_id),
    booking_agegroup INTEGER NOT NULL REFERENCES agegroup(agegroup_id),
    booking_comment TEXT,
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

CREATE TABLE agegroup (
    agegroup_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    agegroup_name TEXT NOT NULL
);

CREATE TABLE syscfg (
    syscfg_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    syscfg_json TEXT NOT NULL,
    syscgg_ts TIMESTAMP NOT NULL
);

DROP TABLE cbuser;
CREATE TABLE IF NOT EXISTS cbuser (
    cbuser_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    cbuser_login TEXT UNIQUE,
    cbuser_family TEXT,
    cbuser_given TEXT,
    cbuser_password TEXT,
    cbuser_note TEXT,
    cbuser_calendar_tag TEXT,
    cbuser_pin INTEGER 
        DEFAULT (substr(random() || '0000000',1,7))
);

-- add an extra right for people who can edit

INSERT INTO cbright (cbright_key,cbright_label)
    VALUES 
        ('booker','Booker');

