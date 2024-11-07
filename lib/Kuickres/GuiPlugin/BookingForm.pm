package Kuickres::GuiPlugin::BookingForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::Util qw(dumper);
use Time::Piece qw(localtime);
use POSIX qw(strftime);
use Kuickres::Model::Email;
use Mojo::JSON qw(true false to_json from_json);
use Role::Tiny::With;

with 'Kuickres::Role::BookingHelper';

=head1 NAME

Kuickres::GuiPlugin::BookingForm - Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::BookingForm;

=head1 DESCRIPTION

The Booking Edit Form

=cut

has checkAccess => sub ($self) {
    return $self->user->may('booker') || $self->user->may('admin');
};

has singleRoom => sub ($self) {
    my $rooms = $self->db->select('room','*',undef,{
        limit => 2
    })->hashes;
    return false if $rooms->size > 1;
    return $rooms->first->{room_id};
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

sub db {
    return shift->user->mojoSqlDb;
}


=head2 formCfg

Returns a Configuration Structure for the Booking Entry Form.

=cut


has formCfg => sub {
    my $self = shift;
    my $db = $self->db;
    my $adm = $self->user->may('admin');
    my $room = $db->select('room','room_id')->hash->{room_id};

    my $districts = $db->select(
        'district',[\"district_id AS key",\"district_name AS title"],{district_active => 1},'district_id'
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
    my $users = $db->select(
        'cbuser',[\"cbuser_id AS key",\"cbuser_login AS title"],undef,'cbuser_login'
    )->hashes->to_array;
    unshift @$users, {
        key => undef, title => 'Select a user'
    };

    my $eq_title = trm('Equipment');
    my $form = $self->args->{currentFormData};
    $form->{booking_cbuser} = $self->user->userId if not $adm;

    my $t = eval { $self->parseTime(
        $form->{booking_date},
        $form->{booking_from},
        $form->{booking_to},
    ) };
    # $self->log->debug($@) if $@;
    # $self->log->debug("T:",dumper($t));
    #$self->log->debug("F:",dumper($form));
    my @equipment;
    my $eqHash = $self->getEqHash($form->{booking_cbuser},$form->{booking_room});
    
    $db->select(
        'equipment','*',{
            equipment_room => $room
        }
    )->hashes->map(sub ($rec) {
        my $enable = false;
        $self->log->debug("EQ CHECK:",dumper($t,$eqHash,$rec));
        if ($eqHash->{$rec->{equipment_id}}
            and $t
            and $t->{start_ts} < $rec->{equipment_end_ts}
            and $t->{end_ts} > $rec->{equipment_start_ts}
        ){
            $enable = true;
        }
        push @equipment, {
            label => '',
            key => 'eq_'.$rec->{equipment_id},
            reloadOnFormReset => true,
            widget => 'checkBox',
            set => {
                label => $rec->{equipment_name} .
                    ' ['.$rec->{equipment_cost}.'p]',
                enabled => $enable
            }
        };
    });
    #$self->log->debug('EQ:',dumper(\@equipment));

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
            triggerFormReset => true,
            reloadOnFormReset => false,
            cfg => {
                structure => $users,
            },
            validator => sub {
                my $value = shift;
                my $fieldName = shift;
                return trm("Invalid user") 
                    unless $value eq $self->user->userId 
                        or $self->user->may('admin');
                return;
            },
        }
        :(),
        ($self->singleRoom ? 
            {
                key => 'booking_room',
                label => '',
                widget => 'hiddenText',
                set => {
                    readOnly => true,
                },
                getter => sub {
                    $self->singleRoom
                }
            } : {
                key => 'booking_room',
                label => trm('Room'),
                widget => 'selectBox',
                cfg => {
                    structure => $db->select(
                        'room',[\"room_id AS key",\"room_name AS title"],undef,'room_name'
                    )->hashes->to_array
                }
            }),
        {
            label => trm('Date'),
            widget => 'header'
        },
        {
            key => 'booking_date',
            label => trm('Date'),
            widget => 'date',
            triggerFormReset => true,
            set => {
                maxWidth => 100,
                required => true,
            },
            validator => sub ($value,$fieldName,$form) {
                if ($value !~ /^\d+$/) {
                    return trm("Epoch seconds only")
                }
                if ($value < time-24*3600) {
                    return trm("Can't book in the past.")
                }
                return;
            }
        },
        {
            key => 'booking_from',
            label => trm('Start Time'),
            widget => 'comboBox',
            triggerFormReset => true,
            reloadOnFormReset => false,
            set => {
                required => true,
                maxWidth => 100,
            },
            cfg => {
                structure => [
                    map {
                        strftime("%H:%M",gmtime($_*30*60));
                    } ( (7*2)..(18*2) )
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
            triggerFormReset => true,
            reloadOnFormReset => false,
            set => {
                maxWidth => 100,
                required => true,
            },
            cfg => {
                structure => [
                    map {
                        strftime("%H:%M",gmtime($_*30*60));
                    } ( (8*2)..(18*2) )
                ]
            },
            validator => sub ($value,$fieldName,$form) {
                return trm("HH:MM expected")
                    if $value !~ /^\d{1,2}:\d{2}$/;
                my $t = eval { $self->parseTime(
                    $form->{booking_date},
                    $form->{booking_from},
                    $form->{booking_to}
                )};
                if ($@) {
                    $self->log->debug($@);
                    return trm("Invalid Date/Time specification");
                }
                return trm("Room is not open from %1 to %2.",
                    strftime("%d.%m.%Y %H:%M",localtime($t->{start_ts})),
                    strftime("%H:%M",localtime($t->{end_ts})),
                )
                unless $self->isRoomOpen($form->{booking_room},$t->{start_ts},$t->{end_ts});

                my @params = (
                    $form->{booking_room},
                    $t->{start_ts},
                    $t->{end_ts}
                );

                return trm("Can't book in the past.") 
                    if $t->{start_ts} < time;

                return;
            },
        },
        {
            label => trm('Anlagen'),
            widget => 'header'
        },
        @equipment,
        {
            label => trm('Contact Data'),
            widget => 'header'
        },
        {
            key => 'booking_mobile',
            label => trm('Mobile Phone'),
            widget => 'text',
            set => {
                required => true,
                placeholder => trm("07x xxx xxxx")
            },
            validator => sub ($value,$field,$form) {
                $value =~ /^07\d(?:\s*\d\s*){7}$/
                or return trm("Phone number 07x xxx xxxx expected");
                return;
            }
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
    Kuickres::Model::Email->new( app=> $self->app, log=>$self->log );
};

has actionCfg => sub {
    my $self = shift;
    my $type = $self->config->{type} // 'add';
    my $handler = sub {
        my $self = shift;
        my $args = shift;
        my %metaInfo;
        my $t = $self->parseTime($args->{booking_date},
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
        }
        my @eq_list;
        my @equipmentList;
        for my $key (keys %$args){
            next if $key !~ /^eq_(\d+)/;
            my $eq_id = $1;
            if (my $eq = $self->db->select('equipment','*',{
                equipment_id => $eq_id,
                equipment_room => $args->{booking_room}
            })->hash){
                if ($args->{$key}) {
                    push @eq_list, $eq_id;
                    push @equipmentList, $eq->{equipment_name};
                }
            }
            else {
                die mkerror(17433,
                    trm("Equipment %1 is not in this room",$eq_id));
            }
        }
        die mkerror(3894,trm("No Equipment Selected")) unless @eq_list;
        my @bookArgs = (
            $args->{booking_cbuser},
            $args->{booking_start_ts},
            $t->{end_ts},
            $args->{booking_room},
            \@eq_list,
            $args->{booking_id}
        );
        
        if (my $overlaps = $self->getBookings(@bookArgs)){
            return {
                action => 'showMessage',
                title => trm("Booking Problem"),
                html => true,
                message => trm("Your booking overlaps with BookingIds: %1",join(", ", @{$overlaps->{desc_array}}))
            }
        }

        my $issues = $self->checkResourceAllocations(@bookArgs);
        
        if ($issues) {
            return {
                action => 'showMessage',
                title => trm("Booking Problem"),
                html => true,
                message => trm("Booking was not possible because: <ul>%1</ul>",join("\n",map { "<li>$_</li>"} @$issues)),
            }
        }

        $args->{booking_equipment_json} = to_json(\@eq_list);
        my $db = $self->db;
        my $tx = $db->begin;
        my $data = { map { "booking_".$_ => $args->{"booking_".$_} }
            qw( cbuser room start_ts duration_s mobile school
            district equipment_json agegroup create_ts) };
        my $ID = $args->{booking_id};
        if ($type eq 'add')  {
            my $res = $db->insert('booking',$data);
            $ID = $metaInfo{recId} = $res->last_insert_id;
        }
        else {
            if ($db->select('booking',
                'booking_start_ts',{
                    booking_id => $args->{booking_id}
                })->hash->{booking_start_ts} < time){
                die mkerror(6534,trm("Can't modify booking in the past. Please close the form."))
            }
            $db->update('booking',$data,{
                booking_id => $args->{booking_id},
                %USER
            });
        }
        my $room = $db->select(['room', [
            'location', 'location_id' => 'room_location']],
            [qw(room_name location_name location_address)],
            {
                room_id => $args->{booking_room}
            }
        )->hash or die mkerror(3874,"Room not found");

        my $userInfo = $db->select('cbuser',undef,{
            cbuser_id => $args->{booking_cbuser}
        })->hash or die mkerror(3874,"User not found");
        
        $self->mailer->sendMail({
            to => $userInfo->{cbuser_login},
            template => 'booking',
            args => {
                id => $ID,
                date => strftime(trm('%d.%m.%Y'),localtime($args->{booking_start_ts})),
                location => $room->{location_name} . ' - ' . $room->{location_address},
                room => $room->{room_name},
                equipmentList => \@equipmentList,
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

sub getAllFieldValues ($self,$args,$form,$lang) {
    #$self->log->debug("ARGS,FORM,LANG:",dumper $args,$form,$lang);
    if ($self->config->{type} ne 'edit'){
        my $user = $self->user->userId;
        my $room = ($args->{selection}{room_id} // $self->singleRoom);
        my $eqHash = $self->getEqHash($user,$room);
        $self->log->debug("ALLL EQ",dumper $eqHash);
        return {
            booking_cbuser => $user,
            booking_room => $room,
            ( map {
                "eq_".$_ => $form->{currentFormData}{"eq_".$_} // false
            } keys %{$eqHash} )
        };
    }

    my $id = $args->{selection}{booking_id};
    die mkerror(trm("No booking selected")) unless $id;
    my $WHERE = {
        booking_id => $id
    };
    if (not $self->user->may('admin')) {
        $WHERE->{booking_cbuser} = $self->user->userId
    }
    my $rec = $self->db->select('booking',[\'*',
        \"booking_start_ts AS booking_date",
        \"strftime('%H:%M',booking_start_ts,'unixepoch','localtime')
        AS booking_from",
        \"strftime('%H:%M',booking_start_ts+booking_duration_s,'unixepoch','localtime') AS booking_to"],
        $WHERE
    )->hash;
    my $eqMapForm = { map { $_ => true } @{
        from_json($rec->{booking_equipment_json})}
    };
    my @ids = sort keys %{$self->getEqHash($rec->{booking_cbuser},$rec->{booking_room})};
    for my $eqId ( @ids ){
        $rec->{"eq_".$eqId} = $eqMapForm->{$eqId} ? true : false;
    }
    return $rec;
}

has grammar => sub ($self) {
    $self->mergeGrammar(
        $self->SUPER::grammar,
        {
            _vars => [ qw(type) ],
            _mandatory => [ qw(type) ],
            type => {
                _doc => 'type of form to show: edit, add',
                _re => '(edit|add)'
            },
        }
    );
};

1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
