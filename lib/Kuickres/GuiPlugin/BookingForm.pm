package Kuickres::GuiPlugin::BookingForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Mojo::Util qw(dumper);
use Time::Piece qw(localtime);
use POSIX qw(strftime);
use Kuickres::Email;

=head1 NAME

Kuickres::GuiPlugin::BookingForm - Song Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::BookingForm;

=head1 DESCRIPTION

The Booking Edit Form

=cut

has checkAccess => sub {
    my $self = shift;
    return 0 if $self->user->userId eq '__ROOT';
    return $self->user->may('booker') || $self->user->may('admin');
};

has singleRoom => sub ($self) {
    my $rooms = $self->db->query(<<SQL_END)->hashes;
SELECT * FROM room LIMIT 2;
SQL_END
    return false if $rooms->size > 1;
    return $rooms->first->{room_id};
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

sub db {
    shift->user->mojoSqlDb;
}


=head2 formCfg

Returns a Configuration Structure for the Booking Entry Form.

=cut

sub parse_time ($self,$date,$from,$to) {
    my $date_str = strftime("%d.%m.%Y",gmtime($date));
    my $start_ts = eval { 
        localtime->strptime("$date_str $from",'%d.%m.%Y %H:%M')->epoch };
    die trm("Error parsing %1","$date_str $from")
        if $@;
    
    $from =~ /^(\d{1,2}):(\d{2})$/;
    my $start = $1*3600+$2*60;
    $to =~ /^(\d{1,2}):(\d{2})$/;
    my $end = $1*3600+$2*60;
    my $duration = $end - $start;
    my $end_ts = $start_ts + $duration;
    my $ret = {
        start_ts => $start_ts,
        start => $start,
        end => $end,
        end_ts => $end_ts,
        duration => $duration,
    };
    # $self->log->debug(dumper $ret);
    return $ret;
}

has formCfg => sub {
    my $self = shift;
    my $db = $self->db;
    my $adm = $self->user->may('admin');
    my $districts = $db->select(
        'district',[\"district_id AS key",\"district_name AS title"],undef,'district_id'
    )->hashes->to_array;
    if ($self->config->{type} eq 'add'){
        unshift @$districts, {
            key => undef, title => trm("Select District")
        }
    }
    my $agegroups = $db->select(
        'agegroup',[\"agegroup_id AS key",\"agegroup_name AS title"],undef,'agegroup_id'
    )->hashes->to_array;
    if ($self->config->{type} eq 'add'){
        unshift @$agegroups, {
            key => undef, title => trm("Select Agegroup")
        }
    }
    return [
        $self->config->{type} eq 'edit' ? {
            key => 'booking_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),
        $adm
        ? {
            key => 'booking_cbuser',
            label => trm('User'),
            widget => 'selectBox',
            cfg => {
                structure => $db->select(
                    'cbuser',[\"cbuser_id AS key",\"cbuser_login AS title"],undef,'cbuser_login'
                )->hashes->to_array
            },
            validator => sub {
                my $value = shift;
                my $fieldName = shift;
                return trm("Invalid user") unless $value eq $self->user->userId or $self->user->may('admin');
                return;
            },
        }
        :(),
        $self->singleRoom ? ():(
            {
                key => 'booking_room',
                label => trm('Room'),
                widget => 'selectBox',
                cfg => {
                    structure => $db->select(
                        'room',[\"room_id AS key",\"room_name AS title"],undef,'room_name'
                    )->hashes->to_array
                }
            },
        ),
        {
            key => 'booking_date',
            label => trm('Date'),
            widget => 'date',
            set => {
                maxWidth => 100,
                required => true,
            },
            validator => sub ($value,$fieldName,$form) {
                if ($value < time-24*3600) {
                    return trm("Can't book in the past.")
                }
                if (not $self->user->may('admin')) {
                    if (my $fd = $self->config->{futureLimitDays}){
                        if (($value - time) > $fd * 24 * 3600) {
                            return trm("No booking more than %1 days in advance",$fd);
                        } 
                    }
                }
                return;
            }
        },
        {
            key => 'booking_from',
            label => trm('Start Time'),
            widget => 'comboBox',
            set => {
                required => true,
                maxWidth => 100,
            },
            cfg => {
                structure => [
                    map {
                        strftime("%H:%M",gmtime($_*30*60));
                    } ( (8*2)..(16*2) )
                ]
            },
            validator => sub ($value,$fieldName,$form) {
                return trm("HH:MM expected")
                    if $value !~ /^\d{1,2}:\d{2}$/;
                return;
            }
        },
        {
            key => 'booking_to',
            label => trm('End Time'),
            widget => 'comboBox',
            set => {
                maxWidth => 100,
                required => true,
            },
            cfg => {
                structure => [
                    map {
                        strftime("%H:%M",gmtime($_*30*60));
                    } ( (8*2)..(16*2) )
                ]
            },
            validator => sub ($value,$fieldName,$form) {
                return trm("HH:MM expected")
                    if $value !~ /^\d{1,2}:\d{2}$/;
                $form->{booking_room} //= $self->singleRoom;
                my $t = eval { $self->parse_time(
                    $form->{booking_date},
                    $form->{booking_from},
                    $form->{booking_to}
                )};
                $self->log->debug(dumper $t);
                if ($@) {
                    $self->log->debug($@);
                    return trm("Invalid Date/Time specification");
                }

                my $location = $db->query(<<SQL_END,
                SELECT 
                    location_name, 
                    location_open_yaml
                FROM location 
                JOIN room ON room_location = location_id 
                WHERE room_id = ?
SQL_END
                $form->{booking_room})->hash;
                return trm("Room %1 not found",$form->{booking_room}) 
                    if not  $location;
                my $oh = Kuickres::Model::OperatingHours->new(
                    $location->{location_open_yaml});
                $self->log->debug(dumper $oh->rules);
                return trm("Location %1 is not open from %2 to %3.",
                    $location->{location_name},
                    strftime("%d.%m.%Y %H:%M",localtime($t->{start_ts})),
                    strftime("%H:%M",localtime($t->{end_ts})),
                )
                unless $oh->isItOpen($t->{start_ts},$t->{end_ts});

                my @params = (
                    $form->{booking_room},
                    $t->{start_ts},
                    $t->{end_ts}
                );

                return trm("Can't book in the past.") if $t->{start_ts} < time;

                my $IGNORE ='';
                if ($form->{booking_id}) {
                    $IGNORE = "AND booking_id <> CAST(? AS INTEGER)";
                    push @params, $form->{booking_id};
                }
                my $overlaps = $db->query(<<SQL_END,@params
                SELECT COUNT(1) AS c
                FROM booking 
                WHERE booking_delete_ts IS NULL 
                AND booking_room = ?
                AND booking_start_ts + booking_duration_s > CAST(? AS INTEGER)
                AND booking_start_ts < CAST(? AS INTEGER)
                $IGNORE
SQL_END
                )->hash;
                return trm("Booking overlaps with %1 existing bookings.",
                    $overlaps->{c}) if $overlaps->{c} > 0;
                return;
            },
        },
        {
            key => 'booking_mobile',
            label => trm('Mobile Phone'),
            widget => 'text',
            set => {
                required => true,
                placeholder => trm("+41 79 xxx xxxx")
            },
        },
        {
            key => 'booking_calendar_tag',
            label => trm('Schedule Text'),
            widget => 'text',
            set => {
                required => true,
                placeholder => trm("Text to show in the schedule")
            },
        },
        {
            key => 'booking_school',
            label => trm('School'),
            widget => 'text',
            set => {
                required => true,
                placeholder => trm("Name of the School")
            },
        },
        {
            key => 'booking_district',
            label => trm('District'),
            widget => 'selectBox',
            set => {
                required => true,
            },
            cfg => {
                structure => $districts
            },
            validator => sub ($value,$field,$form) {
                return trm("please select a district")
                    unless $value;
                return;
            }
        },
        {
            key => 'booking_agegroup',
            label => trm('Age Group'),
            widget => 'selectBox',
            set => {
                required => true,
            },
            cfg => {
                structure => $agegroups
            },
            validator => sub ($value,$field,$form) {
                return trm("please select an agegroup")
                    unless $value;
                return;
            }

        }
    ];
};

has mailer => sub ($self) {
    Kuickres::Email->new( app=> $self->app, log=>$self->log );
};

has actionCfg => sub {
    my $self = shift;
    my $type = $self->config->{type} // 'add';
    my $handler = sub {
        my $self = shift;
        my $args = shift;
        my %metaInfo;
        my $t = $self->parse_time($args->{booking_date},
                    $args->{booking_from},
                    $args->{booking_to});
        $args->{booking_start_ts} = $t->{start_ts};
        $args->{booking_duration_s} = $t->{duration};
        $args->{booking_create_ts} = time;
        $args->{booking_cbuser} //= $self->user->userId;
        $args->{booking_room} //= $self->singleRoom;
        my %USER;
        if (not $self->user->may('admin') and 
            $args->{booking_cbuser} ne $self->user->userId){
            die mkerror(3838,trm("You are not allowed to book in the name of other users."));
            $USER{booking_cbuser} = $self->user->userId;
        }
        my $tx = $self->db->begin;
        my $data = { map { "booking_".$_ => $args->{"booking_".$_} }
            qw( cbuser room start_ts duration_s mobile school
            calendar_tag district agegroup create_ts) };
        my $ID = $args->{booking_id};
        if ($type eq 'add')  {
            my $res = $self->db->insert('booking',$data);
            $ID = $metaInfo{recId} = $res->last_insert_id;
        }
        else {
            if ($self->db->select('booking',
                'booking_start_ts',{
                    booking_id => $args->{booking_id}
                })->hash->{booking_start_ts} < time){
                die mkerror(6534,trm("Can't modify booking in the past. Please close the form."))
            }
            $self->db->update('booking',$data,{
                booking_id => $args->{booking_id},
                %USER
            });
        }
        my $room = $self->db->query(<<SQL_END,$args->{booking_room})->hash
        SELECT room_name,location_name, location_address 
        FROM room JOIN location ON room_location = location_id
        WHERE room_id = ?
SQL_END
        or die mkerror(3874,"Room not found");

        my $userInfo = $self->db->select('cbuser',undef,{
            cbuser_id => $args->{booking_cbuser}
        })->hash or die mkerror(3874,"User not found");
        
        $self->mailer->sendMail({
            to => $userInfo->{cbuser_login},
            from => $self->config->{from},
            template => 'booking',
            args => {
                id => $ID,
                date => strftime(trm('%d.%m.%Y'),localtime($args->{booking_start_ts})),
                location => $room->{location_name} . ' - ' . $room->{location_address},
                room => $room->{room_name},
                time => $args->{booking_from}.' - '.$args->{booking_to},
                accesscode => $userInfo->{cbuser_pin},
                email => $userInfo->{cbuser_login},
            }
        });
        $tx->commit;
        return {
            action => 'dataSaved',
            metaInfo => \%metaInfo
        };
    };

    return [
        {
            label => $type eq 'edit'
               ? trm('Save Changes')
               : trm('Add Booking'),
            action => 'submit',
            key => 'save',
            actionHandler => $handler
        }
    ];
};

has grammar => sub {
    my $self = shift;
    $self->mergeGrammar(
        $self->SUPER::grammar,
        {
            _vars => [ qw(type) ],
            type => {
                _doc => 'type of form to show: edit, add',
                _re => '(edit|add)'
            },
        },
    );
};

sub getAllFieldValues {
    my $self = shift;
    my $args = shift;
    return {} if $self->config->{type} ne 'edit';
    my $id = $args->{selection}{booking_id};
    return {} unless $id;
    my $WHERE = {
        booking_id => $id
    };
    if (not $self->user->may('admin')) {
        $WHERE->{booking_cbuser} = $self->user->userId
    }
    return $self->db->select('booking',['*',
        \"booking_start_ts AS booking_date",
        \"strftime('%H:%M',booking_start_ts,'unixepoch','localtime')
        AS booking_from",
        \"strftime('%H:%M',booking_start_ts+booking_duration_s,'unixepoch','localtime') AS booking_to"],
        $WHERE
    )->hash;
}

has grammar => sub {
    my $self = shift;
    $self->mergeGrammar(
        $self->SUPER::grammar,
        {
            _vars => [ qw(from futureLimitDays) ],
            _mandatory => [ qw(from) ],
            from => {
                _doc => 'sender for mails',
            },
            futureLimitDays => {
                _doc => 'Keine Buchungen mehr als X Tage in der Zukunft, ohne admin'
            }
        },
    );
};

1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
