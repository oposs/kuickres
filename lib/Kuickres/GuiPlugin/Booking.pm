package Kuickres::GuiPlugin::Booking;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false from_json);
use Mojo::Util qw(dumper);
use Text::ParseWords;
use POSIX qw(strftime);
use DBI qw(:sql_types);

=head1 NAME

Kuickres::GuiPlugin::Booking - Booking Table

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::Booking;

=head1 DESCRIPTION

The Table Gui.

=cut

has checkAccess => sub ($self) {
    return $self->user->may('booker') || $self->user->may('admin');
};


=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractTable> plus:

=cut

=head2 formCfg

=cut

has formCfg => sub {
    my $self   = shift;
    my $eqList = $self->db->select(
        'equipment',
        [ \"equipment_id AS key", \"equipment_name AS title" ],
        undef,
        {
            order_by => ['equipment_name']
        }
    )->hashes->to_array;
    return [
        {
            key    => 'show_past',
            widget => 'checkBox',
            set => {
                label  => trm('Show old bookings'),
            }
        },
        {
            widget => 'selectBox',
            key    => 'day_filter',
            cfg    => {
                structure => [
                    { key => undef, title => trm('Show All Days') },
                    { key => '0',     title => trm('Sun') },
                    { key => '1',     title => trm('Mon') },
                    { key => '2',     title => trm('Tue') },
                    { key => '3',     title => trm('Wed') },
                    { key => '4',     title => trm('Thu') },
                    { key => '5',     title => trm('Fri') },
                    { key => '6',     title => trm('Sat') }
                ]

            }
        },
        {
            key    => 'eq_filter',
            widget => 'selectBox',
            #set => {
            #    minWidth => '200',
            #},
            cfg    => {
                structure => [
                    {
                        key   => undef,
                        title => trm('Show All Equipment')
                    },
                    @$eqList
                ]
            }
        },
        {
            key    => 'search',
            widget => 'text',
            set    => {
                width       => 200,
                placeholder => trm('search words ...'),
            },
        },
    ];
};

=head2 tableCfg


=cut

has tableCfg => sub {
    my $self = shift;
    my $adm = $self->user->may('admin');
    return [
        {
            label => trm('Id'),
            type => 'number',
            width => '1*',
            key => 'booking_id',
            sortable => true,
            primary => true
        },
        ( $self->singleRoom ? ():({
            label => trm('Room'),
            type => 'string',
            width => '4*',
            key => 'room_name',
            sortable => true,
        })),
        {
            label => trm('User'),
            type => 'string',
            width => '5*',
            key => 'cbuser_login',
            sortable => true,
        },
        {
            label => trm('Date'),
            type => 'date',
            width => '3*',
            key => 'booking_start_ts',
            sortable => true,
            format => trm('dd.MM.yyyy'),
        },
        {
            label => trm('Time'),
            type => 'string',
            width => '3*',
            key => 'booking_time',
            sortable => false,
        },
        {
            label => trm('School'),
            type => 'string',
            width => '3*',
            key => 'booking_school',
            sortable => true,
        },
        {
            label => trm('Equipment'),
            type => 'string',
            width => '3*',
            key => 'booking_equipment',
            sortable => false,
        },
        ($adm ? (
        {
            label => trm('District'),
            type => 'string',
            width => '2*',
            key => 'district_name',
            sortable => true,
        },
        {
            label => trm('Age Group'),
            type => 'string',
            width => '2*',
            key => 'agegroup_name',
            sortable => true,
        },
        {
            label => trm('MBooking'),
            type => 'string',
            width => '1*',
            key => 'booking_mbooking',
            sortable => true,
        },
        ):()),
        {
            label => trm('Created'),
            type => 'date',
            width => '3*',
            key => 'booking_create_ts',
            format => trm('dd.MM.yyyy HH:mm'),
            sortable => true,
        },
        {
            label => trm('Used'),
            type => 'date',
            width => '3*',
            key => 'access_log_entry_ts',
            format => trm('dd.MM.yyyy HH:mm'),
            sortable => true,
        },
        ($adm ? ( {
            label => trm('Deleted'),
            type => 'date',
            width => '3*',
            format => trm('dd.MM.yyyy HH:mm'),
            key => 'booking_delete_ts',
            sortable => true,
        } ):())
    ]
};

=head2 actionCfg

Only users who can write get any actions presented.

=cut

has actionCfg => sub {
    my $self = shift;
    # return [] if $self->user and not $self->user->may('admin');
    my $adm = $self->user && $self->user->may('admin');
    return [
        {
            label => trm('New Booking'),
            action => 'popup',
            addToContextMenu => false,
            name => 'BookingAddForm',
            key => 'add',
            popupTitle => trm('New Booking'),
            set => {
                height => 700,
                width => 350
            },
            backend => {
                plugin => 'BookingForm',
                config => {
                    type => 'add',
                }
            }
        },
        {
            label => trm('Edit Booking'),
            action => 'popup',
            addToContextMenu => true,
            defaultAction => true,
            name => 'BookingEditForm',
            key => 'edit',
            popupTitle => trm('Edit Booking'),
            set => {
                height => 700,
                width => 350,
            },
            buttonSet => {
                enabled => false
            },
            backend => {
                plugin => 'BookingForm',
                config => {
                    type => 'edit',
                }
            }
        },
        {
            label => trm('Delete Booking'),
            action => 'submitVerify',
            addToContextMenu => true,
            question => trm('Do you really want to delete the selected Booking.'),
            buttonSet => {
                enabled => false
            },
            key => 'delete',
            actionHandler => sub {
                my $self = shift;
                my $args = shift;
                my $tx = $self->db->begin;
                my $id = $args->{selection}{booking_id};
                my %USER;
                if (not $self->user->may('admin')){
                    $USER{booking_cbuser} = $self->user->userId;
                }
                die mkerror(3843,trm("Bookings in the past can not be deleted"))
                    if $args->{selection}{booking_start_ts} < time;
                eval {
                    $self->db->update('booking',{booking_delete_ts => time},{
                        booking_id => $id,
                        booking_start_ts => { 
                            '>' => time},
                        %USER,
                        booking_delete_ts => undef
                    });
                };
                if ($@){
                    $self->log->error("remove booking $id: $@");
                    die mkerror(4993,trm("Failed to remove booking %1",$id));
                }
                my $b = $self->db->query(<<'SQL_END',$id)->hash
        SELECT 
            cbuser_login,
            booking_start_ts,
            room_name,
            location_name
        FROM booking
        JOIN cbuser ON booking_cbuser = cbuser_id
        JOIN room ON booking_room = room_id
        JOIN location ON room_location = location_id
        WHERE booking_id = ? AND booking_delete_ts IS NOT NULL
SQL_END
                or die mkerror(3874,trm("Failed to remove booking %1",$id));

                $self->mailer->sendMail({
                    to => $b->{cbuser_login},
                    template => 'booking-rm',
                    args => {
                        id => $id,
                        date => strftime(trm('%d.%m.%Y'),
                            localtime($b->{booking_start_ts})),
                        location => $b->{location_name},
                        room => $b->{room_name},
                        email => $b->{cbuser_login},
                    }
                });
                $tx->commit;
                return {
                    action => 'reload',
                };
            }
        },
        $adm ? $self->makeExportAction() : (),
    ];
};

has singleRoom => sub ($self) {
    my $rooms = $self->db->select('room','*',undef,{
        limit => 2
    })->hashes;
    return false if $rooms->size > 1;
    return $rooms->first->{room_id};
};

has mailer => sub ($self) {
    Kuickres::Model::Email->new( app=> $self->app, log=>$self->log );
};

sub db {
    return shift->user->mojoSqlDb;
};

my $FROM = ['booking',
        ['cbuser','cbuser_id','booking_cbuser'],
        ['room','room_id','booking_room'],
        ['agegroup','agegroup_id','booking_agegroup'],
        ['district','district_id','booking_district'],
        [-left => \'(SELECT access_log_booking, MIN(access_log_entry_ts) AS access_log_entry_ts
                FROM access_log GROUP BY access_log_booking) AS al','al.access_log_booking','booking_id']];

my $keyMap = {
    id => 'booking_id',
    room => 'room_name',
    user => 'cbuser_login',
    date => sub { 
        \["strftime('%d.%m.%Y',booking_start_ts,'unixepoch', 'localtime') = ?",shift] }
};

sub WHERE {
    my $self = shift;
    my $args = shift;
    my $where = $self->user->may('admin')
        ? {
            -and => []
        } 
        : {
            -and => [
                booking_delete_ts => undef
            ]
        };
    if ($args->{formData}{show_past}) {
        push @{$where->{-and}},
            \[ "booking_start_ts < ?", {
                type => SQL_INTEGER, value => time}];
    }
    else {
        push @{$where->{-and}},
            \[ "booking_start_ts + booking_duration_s > ?", { 
                type => SQL_INTEGER, value => time}];
    }
    if (defined $args->{formData}{day_filter}) {
        push @{$where->{-and}},
        \["CAST(strftime('%w',booking_start_ts,'unixepoch', 'localtime') AS INTEGER) = ?", { type => SQL_INTEGER, value => int($args->{formData}{day_filter})}];
    }
    if (defined $args->{formData}{eq_filter}) {
        push @{$where->{-and}},
        [\["? in (SELECT CAST(json_each.value AS INTEGER) FROM json_each(booking_equipment_json))", { type => SQL_INTEGER, value => $args->{formData}{eq_filter}}],{ booking_equipment_json => '[0]'}];
    }
    #$self->log->debug(dumper $where);
    if (my $str = $args->{formData}{search}) {
        chomp($str);
        for my $search (quotewords('\s+', 0, $str)){
            chomp($search);
            my $match = join('|',keys %$keyMap);
            if ($search =~ m/^($match):(.+)/){
                my $key = $keyMap->{$1};
                push @{$where->{-and}},
                    ref $key eq 'CODE' ?
                    $key->($2) : ($key => $2) 
            }
            else {
                my $lsearch = "%${search}%";
                push @{$where->{-and}}, (
                    -or => [
                        room_name => { -like => $lsearch },
                        booking_id => $search,
                        cbuser_login => { -like => $lsearch},
                        \["strftime('%Y-%m-%d',booking_start_ts,'unixepoch', 'localtime') LIKE ?", $lsearch ]
                    ]
                )
            }
        }
    }
    return $where;
}

sub getTableRowCount {
    my $self = shift;
    my $args = shift;
    return $self->db->select($FROM,'COUNT(*) AS count',$self->WHERE($args))->hash->{count};
}

sub getTableData {
    my $self = shift;
    my $args = shift;
    my $SORT = {
        -asc => 'booking_start_ts'
    };
    my $db = $self->db;
    if ( my $sc = $args->{sortColumn}){
        $SORT = {
            
                $args->{sortDesc}
                ? '-desc' 
                : '-asc',
                $sc
            };        
    }
    my $adm = $self->user && $self->user->may('admin');
    my $data = $db->select($FROM,[
                  'booking.*',
                'room_name',
        ( $adm ? (
            'agegroup_name',
            'district_name',
        ):()),
        'cbuser_login',
        'cbuser_id', 
        \'booking_start_ts * 1000 AS booking_start_ts',
        \'access_log_entry_ts * 1000 AS access_log_entry_ts',
        \"strftime('%H:%M',booking_start_ts,'unixepoch', 'localtime') || '-' ||
        strftime('%H:%M',booking_start_ts+booking_duration_s,'unixepoch','localtime') AS booking_time",
        \'booking_create_ts * 1000 AS booking_create_ts',
        ( $adm ? (
            \'booking_delete_ts * 1000 AS booking_delete_ts' ): ()
        ),  
                ],
                $self->WHERE($args),
                {
                    order_by => $SORT,
                    limit => $args->{lastRow}-$args->{firstRow}+1,
                    offset => $args->{firstRow}
                }
    )->hashes->to_array;

    my %eqLookup = ( 0 => trm('Alles'));

    $db->select('equipment',[qw(equipment_id equipment_key)])->hashes->map(sub { $eqLookup{$_->{equipment_id}} = $_->{equipment_key}});
    
    for my $row (@$data) {
        my $ok = false;
        my $mine = delete $row->{cbuser_id} == $self->user->userId;
        
        $row->{booking_equipment} = join(', ', 
            map { $eqLookup{$_} // '?'} 
                @{from_json($row->{booking_equipment_json})})
                if %eqLookup and $row->{booking_equipment_json};
        if (not $mine and not $adm){
            delete $row->{cbuser_login};
            delete $row->{cbuser_comment};
        }
        if (($mine or $adm )
            and not $row->{booking_delete_ts}
            and $row->{booking_start_ts} > time
        ){
                $ok = true;
        }
        $row->{_actionSet} = {
            edit => {
                enabled => $ok
            },
            delete => {
                enabled => $ok,
            },
        }
    }
    return $data;
}

1;

__END__

=head1 COPYRIGHT

Copyright (c) 2020 by Tobias Oetiker. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
