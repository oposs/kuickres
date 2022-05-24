package Kuickres::Role::BookingHelper;
use Role::Tiny;
use Mojo::Base -base, -signatures;
use YAML::XS;
use JSON::Validator;
use Mojo::JSON qw(true false to_json from_json);
use Encode;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::Util qw(dumper);
use Kuickres::Model::OperatingHours;
use Time::Piece qw(localtime gmtime);
use DBI qw(:sql_types);

with 'Kuickres::Role::JsonField';

=head1 NAME

Kuickres::Model::Booking - booking table management

=head1 SYNOPSIS


=head1 DESCRIPTION

A friendly interface to the booking table

=cut

=head2 METHODS

=head3 getUserCatRules(user_id) 

Retrieve per user category rules on reservation restrictions

returns hash

=cut

sub getUserCatRules ( $self, $user_id){
    my $rec = $self->db->select(
        [ 'usercat', [ 'cbuser', 'cbuser_usercat', 'usercat_id' ] ],
        'usercat.*',
        {
            cbuser_id => $user_id
        }
    )->hash;
    return from_json( $rec->{usercat_rule_json} || '{}' );
}

=head3 getEqHash(user)

Get a map of equipment the user has permission to use

=cut

sub getEqHash ( $self, $user_id,$room_id ) {
    my $db     = $self->db;
    my $ucr    = $self->getUserCatRules($user_id);
    my $eqList = $ucr->{equipmentList} || [];
    my %hash;
    $db->select(
        'equipment',
        '*',
        {
            equipment_room => $room_id,
            $self->user->may('admin')
            ? ()
            : ( equipment_key => { -in => $eqList } )
        }
    )->hashes->map(
        sub ($rec) {
            $hash{ $rec->{equipment_id} } = true;
        }
    );
    #$self->log->debug('EQHASH',$user_id,$room_id,dumper \%hash);
    return \%hash;
}

=head3 checkResourceAllocations(user,start,end,room,equipment,exclude)

check if this booking is ok or return list of issues

=cut

sub checkResourceAllocations ( $self, $user, $start, 
    $end, $room, $equipment, $exclude = undef ) {
    my @issues;
    # eq check
    my $db = $self->db;

    if ($start >= $end) {
        push @issues, trm("Startzeit muss vor Endzeit sein");
    }

    #### check opening hours
    if (not $self->isRoomOpen( $room, $start, $end ) ) {
        push @issues, trm(
            "Raum ist nicht verfügbar für Reservationen von %1 - %2",
            localtime($start)->strftime("%H:%M"),
            localtime($end)->strftime("%H:%M"),
        );
        return \@issues;
    }

    #### check equipment availability
    my $eqUserHash = $self->getEqHash($user,$room);
    my $eqReqHash  = { map { $_ => true } @$equipment };

    my $eqp = 0;
    $db->select(
        'equipment',
        '*',
        {
            equipment_room => $room,
            equipment_id   => { -in => $equipment }
        }
    )->hashes->map(
        sub ($rec) {
            my $eqId = $rec->{equipment_id};
            if (not $eqUserHash->{$eqId} and not $self->user->may('admin')) {
                push @issues, trm( "Benutzer hat keine Erlaubnis die Anlage  %1 zu buchen.", $rec->{equipment_name});
            }

            if ($end < $rec->{equipment_start_ts}
              or $start > $rec->{equipment_end_ts}) {
                push @issues, trm(
                    "Anlage %1 ist im gewünschten Zeitraum nicht verfügbar.",
                    $rec->{equipment_name}
                )
            }            
            $eqp += $rec->{equipment_cost};
        }
    );


    if ($self->user->may('admin')){
        return @issues ? \@issues : undef;
    };
    
    ## these rules only apply to non-admin users ##

    my $rules = $self->getUserCatRules($user);

    if ($eqp > $rules->{maxEquipmentPointsPerBooking}) {
        push @issues, 
            trm("Mehr als %1 Anlage Punkte (%2) in einer einzelnen Reservation",
                $rules->{maxEquipmentPointsPerBooking},$eqp
            );
    };

    if ($end > time + $rules->{futureBookingDays} * 24 * 3600) {
        push @issues, trm("Buchung liegt mehr als %1 Tage in der Zukunft",
            $rules->{futureBookingDays}
        );
    }

    my $duration = $end - $start;
    my $day_start = localtime($start)->truncate(to=>'day');
    my $day_end   = ($day_start + 36*3600)->truncate(to=>'day');
    #$self->log->debug("exclude:",$exclude);
    #$self->log->debug("start:",$day_start->strftime);
    #$self->log->debug("end:",$day_end->strftime);
    my $bookings = $db->select(
        'booking',
        '*',
        { -and => [
            booking_delete_ts => undef,
            booking_cbuser    => $user,
            -bool => \["booking_start_ts  > ?", { 
                type=> SQL_INTEGER, value =>  $day_start->epoch }],
            -bool => \["booking_start_ts < ?", { 
                type=> SQL_INTEGER, value =>  $day_end->epoch }],
            $exclude ? ( booking_id => { '!=' => $exclude } ) : (),
        ]}
    )->hashes->map(
        sub {
            #$self->log->debug("MINE",dumper $_);
            $duration += $_->{booking_duration_s};
        }
    );

    if ($duration/3600 > $rules->{maxBookingHoursPerDay}) {
        push @issues, trm(
            "Mehr als %1 Stunden (%2h) reserviert in einem einzelnen Tag",
            $rules->{maxBookingHoursPerDay},sprintf("%.1f",$duration/3600)
        );
    }
    if (not $rules->{allowDoubleBooking}) {
        my $overlaps = $db->select(
            'booking',
            '*',
            { -and => [
                booking_delete_ts => undef,
                booking_cbuser    => $user,
                -bool => \["booking_start_ts + booking_duration_s > ?", { 
                    type=> SQL_INTEGER, value =>  $start }],
                -bool => \["booking_start_ts < ?", { 
                    type=> SQL_INTEGER, value =>  $end }],
                $exclude ? ( booking_id => { '!=' => $exclude } ) : (),
            ]}
        )->hashes->map(
            sub {
                push @issues, trm("Im gewünschten Zeitraum existiert schon eine Buchung für deinen Account. Bitte bearbeite die bestehende Buchung.");
            }
        );
    }
    return @issues ? \@issues : undef;
}

=head3 getBookings(user,start,end,room,equipment,exclude)

Return a list of entry descriptions from the booking table, preventing this one from being added.

=cut

sub getBookings ( $self, $user, $start, $end, $room, $equipment,
    $exclude = undef )
{
    my $db = $self->db;
    # $self->log->debug(
    #     dumper {
    #         user      => $user,
    #         start     => $start,
    #         end       => $end,
    #         room      => $room,
    #         equipment => $equipment,
    #         exclude   => $exclude
    #     }
    # );
    my %overlaps;
    $db->select(
        [
            'booking',
            \"json_each(booking.booking_equipment_json)",
        ],
        [
            'booking.*',
            \'CAST(json_each.value AS INTEGER) AS booking_equipment'
        ],
        {
            -and => [
                booking_delete_ts => undef,
                booking_room      => $room,
                -bool             => \[
                    'booking_start_ts + booking_duration_s > ?',
                    {
                        type  => SQL_INTEGER,
                        value => $start
                    }
                ],
                -bool => \[
                    'booking_start_ts < ?',
                    { type => SQL_INTEGER, value => $end }
                ],

                # migrated reservations have the equipment_id 0 
                # in their booking, which means 'everything'
                
                'booking_equipment' => { in => [ @$equipment, 0 ] }, 
                
                $exclude ? ( booking_id => { '!=' => $exclude } ) : (),
            ]
        }
    )->hashes->map(sub ($rec){
        my $desc = 'ID:'.$rec->{booking_id} . ' '
            . localtime($rec->{booking_start_ts})->strftime("%H:%M")
            . ' - '
            . localtime($rec->{booking_start_ts}
                + $rec->{booking_duration_s})->strftime("%H:%M");
        $overlaps{ $rec->{booking_id} }{desc} = $desc;
        push @{$overlaps{ $rec->{booking_id} }{eq}} , $rec->{booking_equipment};
    });
    my @overlaps;
    my %eqs;
    for my $key (sort keys %overlaps) {
        my @eqList;
        $db->select('equipment', '*', {
            $overlaps{$key}{eq}[0] ne '0' ? (equipment_id => { in => $overlaps{$key}{eq} }):() }
        )->hashes->map(sub ($rec) {
            push @eqList, $rec->{equipment_name};
            $eqs{$rec->{equipment_id}} = $rec->{equipment_name};
        });
        push @overlaps, $overlaps{$key}{desc}. ((@eqList) ? ( ': ' . join(', ', @eqList)):'');
    }
    return @overlaps ? { desc_array => \@overlaps, eq_hash => \%eqs } : undef;
}

=head3 parseTime(date,from,to)

Parses a user provided time range. Assuming a european way of specifying date and time.

   date: dd.mm.yyyy
   from: hh:mm
   to: hh:mm

The call returns a hash with the following elements: C<start_ts> (epoch), C<start> (day second), C<end> (day seconds), C<end_ts> (epoch), C<duration> (seconds).

=cut

sub parseTime ( $self, $date, $from, $to ) {
    return unless $date and $from and $to;
    my $date_str = gmtime($date)->strftime("%d.%m.%Y");
    my $start_ts = eval {
        localtime->strptime( "$date_str $from", '%d.%m.%Y %H:%M' )->epoch;
    };
    die trm( "Error parsing %1", "$date_str $from" )
      if $@;

    my $start    = $self->timeToSec($from);
    my $end      = $self->timeToSec($to);
    my $duration = $end - $start;
    my $end_ts   = $start_ts + $duration;
    my $ret      = {
        start_ts => $start_ts,
        start    => $start,
        end      => $end,
        end_ts   => $end_ts,
        duration => $duration,
    };

    # $self->log->debug(dumper $ret);
    return $ret;
}

=head3 timeToSec($time) 

returns seconds and does on bad input

=cut

sub timeToSec ( $self, $time ) {
    if ( $time !~ /^(\d{1,2}):(\d{2})$/ ) {
        die trm( "Error parsing %1", $time );
    }
    return $1 * 3600 + $2 * 60;
}

=head3 isRoomOpen(roomId,start,end)

Returns true or false

=cut 

sub isRoomOpen ( $self, $roomId, $start, $end ) {
    my $db = $self->db;

    my $location = $db->select(
        [
            'location',
            [
                'room', room_location => 'location_id'
            ]
        ],
        undef,
        {
            room_id => $roomId,
        }
    )->hash or return;
    my $oh =
      Kuickres::Model::OperatingHours->new( $location->{location_open_yaml} );
    return $oh->isItOpen( $start, $end );
}

1;
