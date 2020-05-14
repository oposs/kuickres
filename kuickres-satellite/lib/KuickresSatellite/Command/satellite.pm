package KuickresSatellite::Command::satellite;


use Mojo::Base 'Mojolicious::Command', -signatures;
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Pod::Usage;
use Mojo::File;
use Mojo::Util qw(dumper);
use Time::HiRes qw(usleep);
use RPi::Serial;
use RPi::Pin;
use RPi::Const qw(:all);
use Mojo::JSON qw(decode_json encode_json);
use Crypt::ScryptKDF qw(scrypt_hash_verify scrypt_hash);
use Data::Compare qw(Compare);

has description => "satellite\n";
has usage       => <<"EOF";
usage: $0 satellite

    --server=https://kuickres
    --secret=/path/to/secret.file
    --cache=/path/to/cache.file
    --location=1
    --relayOn=0.8

EOF


has opt => sub {
    {
        secret => '/etc/kuickres.secret',
        server => 'http://froburg.oetiker.ch:3626',
        cache => '/var/cache/kuickres.json',
        location => 1,
        relayOn => 0.8,
    };
};

has relay => sub ($self) {
    my $relay = RPi::Pin->new(21);
    $relay->mode(OUTPUT);
    $relay->write(HIGH);
    return $relay;
};

has log => sub ($self) {
    $self->app->log;
};

sub openRelay ($self,$duration) {
    my $relay = $self->relay;
    $relay->write(LOW);
    $self->log->info("Open Relay");
    Mojo::Promise->timer($duration)->then(sub {
    $self->log->info("Close Relay");
        $relay->write(HIGH);
    });       
}


has ua => sub ($self) {
    $self->app->ua;
};

has doorKeys => sub ($self) {
    Mojo::URL->new($self->opt->{server})
        ->path('REST/v1/doorKeys/'.$self->opt->{location});

};
has reportKeyUse => sub ($self) {
    Mojo::URL->new($self->opt->{server})
        ->path('REST/v1/reportKeyUse');

};

has headers => sub ($self) {
    my $secret = Mojo::File->new($self->opt->{secret})->slurp;
    $secret =~ s/\s+$//;
    $secret =~ s/^\s+//;
    
    return {
        'X-API-Key' => $secret
    };
};


has cacheFile => sub ($self) {
    Mojo::File->new($self->opt->{cache});
};

has cache => sub ($self) {
    local $@;
    my $data = eval { 
        decode_json($self->cacheFile->slurp)
    } // { accessCodes => [], keyUseLog => [] };
};



sub startKeypadWatcher ($self) {
    my $ser = RPi::Serial->new("/dev/ttyAMA0",9600);
    my $buffer = '';
    Mojo::IOLoop->recurring(0.1 => sub {
        my $ord = $ser->getc;
        if ($ord >= 0){
           $buffer .= chr($ord);
           if (length($buffer) > 0 && $buffer =~ s/.*\*(\d+)#//){
              my $key = $1;
              $self->log->info("Entered $key");
              if ($self->codeCheck($key)){
                  $self->log->info("Code Valid");              
                  $self->openRelay($self->opt->{relayOn});
              }
           }
        }
    });
}

sub codeCheck ($self,$key) {
    my $now = time;
    for my $row (@{$self->cache->{accessCodes}}) {
        next if $now > $row->{validUntilTs}
            or $now < $row->{validFromTs};
        warn "checking row: ".dumper $row;
        if (scrypt_hash_verify($key,$row->{pinHash})){
            $self->logKeyUse($now,$key,$row);
            return 1;
        }
    }
    return 0;
}

sub logKeyUse ($self,$now,$key,$row) {
    my $cache = $self->cache;
    push @{$cache->{keyUseLog}}, {
        entryTs => $now,
        bookingId => $row->{bookingId},
        hash => scrypt_hash("$row->{bookingId}:$key"),
    };
    $self->storeCache
}

sub storeCache ($self) {
    $self->cacheFile->spurt(encode_json($self->cache));
}

sub startAccessFetcher ($self) {
    Mojo::IOLoop->recurring(10 => sub {
        $self->log->debug("Fetching from ".$self->doorKeys);
        $self->ua->get_p($self->doorKeys->to_string,$self->headers)->then(sub ($tx) {
            my $res = $tx->result;
            if ($res->code == 200){
                my $newCodes = $res->json;
                if (not Compare($newCodes,$self->cache->{accessCodes})){
                    $self->log->info("Got new codes");
                    $self->cache->{accessCodes} = $newCodes;
                    $self->storeCache;
                }
                return;
            }
            $self->log->error($res->message . " - " . $res->body);
        })->catch(sub ($err) {
            $self->log->error($err);
        });
    });
}

sub startKeyUseReporter ($self) {
    Mojo::IOLoop->recurring(5 => sub {
        my $log = $self->cache->{keyUseLog};
        if (@$log) {
            $self->log->info("Pushing ".$self->reportKeyUse);
            $self->ua->post_p($self->reportKeyUse->to_string,$self->headers => json => $log)->then(sub ($tx) {
                my $res = $tx->result;
                if ($res->code == 201) {
                    $self->cache->{keyUseLog} = [];
                    $self->storeCache;
                    return;
                }
                $self->log->error($res->message . " - " . $res->body);
            })
            ->catch(sub ($err) {
                $self->log->error($err);
            });
        }
    });
}

sub run ($self,@args) {
    GetOptionsFromArray \@args, $self->opt,qw(
        help
        verbose
        secret=s
        server=s
        cache=s
        location=i
        relayOn=s
    ) or exit 1;
    $self->headers;
    $self->relay;
    $self->startAccessFetcher;
    $self->startKeypadWatcher;
    $self->startKeyUseReporter;
    print "Started Kuickres Satellite\n";
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

1;