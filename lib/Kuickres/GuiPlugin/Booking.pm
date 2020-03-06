package Kuickres::GuiPlugin::Booking;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Mojo::Util qw(dumper);
use Text::ParseWords;

=head1 NAME

Kuickres::GuiPlugin::Booking - Booking Table

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::Booking;

=head1 DESCRIPTION

The Song Table Gui.

=cut

has checkAccess => sub {
    my $self = shift;
    return 0 if $self->user->userId eq '__ROOT';

    return $self->user->may('booker');
};


=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractTable> plus:

=cut

=head2 formCfg

=cut

has formCfg => sub {
    my $self = shift;
    return [
        {
            key => 'search',
            widget => 'text',
            set => {
                width => 300,
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
        {
            label => trm('Room'),
            type => 'string',
            width => '4*',
            key => 'room_name',
            sortable => true,
        },
        {
            label => trm('User'),
            type => 'string',
            width => '4*',
            key => 'cbuser_login',
            sortable => true,
        },
        {
            label => trm('Date'),
            type => 'string',
            width => '4*',
            key => 'booking_date',
            sortable => true,
        },
        {
            label => trm('Time'),
            type => 'string',
            width => '3*',
            key => 'booking_time',
            sortable => true,
        },
        {
            label => trm('Schedule Entry'),
            type => 'string',
            width => '3*',
            key => 'bookbooking_calendar_tag',
            sortable => true,
        },
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
            label => trm('Comment'),
            type => 'string',
            width => '6*',
            key => 'booking_comment',
            sortable => true,
        },
        {
            label => trm('Created'),
            type => 'string',
            width => '3*',
            key => 'booking_created',
            sortable => true,
        },
        ($adm ? ( {
            label => trm('Deleted'),
            type => 'string',
            width => '3*',
            key => 'booking_deleted',
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

    return [
        {
            label => trm('Add Booking'),
            action => 'popup',
            addToContextMenu => false,
            name => 'bookingAddForm',
            key => 'add',
            popupTitle => trm('New Booking'),
            set => {
                minHeight => 700,
                minWidth => 500
            },
            backend => {
                plugin => 'BookingForm',
                config => {
                    type => 'add'
                }
            }
        },
        {
            action => 'separator'
        },
        {
            label => trm('Edit Booking'),
            action => 'popup',
            addToContextMenu => true,
            defaultAction => true,
            name => 'bookingEditForm',
            key => 'edit',
            popupTitle => trm('Edit Booking'),
            set => {
                minHeight => 700,
                minWidth => 500,
            },
            buttonSet => {
                enabled => false
            },
            backend => {
                plugin => 'BookingForm',
                config => {
                    type => 'edit'
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
                my $id = $args->{selection}{booking_id};
                die mkerror(4992,"You have to select a booking first")
                    if not $id;
                eval {
                    $self->db->update('booking',{booking_delete_ts => time},{booking_id => $id, booking_delete_ts => undef});
                };
                if ($@){
                    $self->log->error("remove booking $id: $@");
                    die mkerror(4993,"Failed to remove booking $id");
                }
                return {
                    action => 'reload',
                };
            }
        }
    ];
};

sub db {
    shift->user->mojoSqlDb;
};

my $FROM = <<FROM_END;
    booking JOIN room ON booking_room = room_id
    JOIN agegroup ON booking_agegroup = agegroup_id
    JOIN district ON booking_district = district_id
    JOIN cbuser ON booking_cbuser = cbuser_id
FROM_END

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
                booking_delete_ts =>undef
            ]
        };
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
    return $self->db->select(\$FROM,'COUNT(*) AS count',$self->WHERE($args))->hash->{count};
}

sub getTableData {
    my $self = shift;
    my $args = shift;
    my $SORT = '';
    my $db = $self->db;
    my $dbh = $db->dbh;
    my $WHERE = $self->WHERE($args);
    if ( $args->{sortColumn} ){
        $SORT = {
            $args->{sortDesc} 
                ? '-desc' 
                : '-asc',
             $args->{sortColumn}
        };        
    }
    my $sql = SQL::Abstract->new;
    my ($from,@from_bind) = $sql->_table($FROM);
    my ($fields,@field_bind) = $sql->_select_fields([
        'booking.*',
        'room_name',
        'agegroup_name',
        'district_name',
        'cbuser_login',
        'cbuser_id', 
        \"strftime('%d.%m.%Y',booking_start_ts,'unixepoch', 'localtime') AS booking_date",
        \"strftime('%H:%M',booking_start_ts,'unixepoch', 'localtime') || '-' ||
        strftime('%H:%M',booking_start_ts+booking_duration_s,'unixepoch','localtime') AS booking_time",
        \"strftime('%d.%m.%Y %H:%M',booking_create_ts,'unixepoch', 'localtime') AS booking_created",
        \"strftime('%d.%m.%Y %H:%M',booking_delete_ts,'unixepoch', 'localtime') AS booking_deleted"
    ]);
    my ($where,@where_bind) = $sql->where($WHERE,$SORT);
    my $data = $db->query("SELECT $fields FROM $from $where LIMIT ? OFFSET ?",
        @from_bind,
        @field_bind,
        @where_bind,
        $args->{lastRow}-$args->{firstRow}+1,
       $args->{firstRow},
    )->hashes;
    for my $row (@$data) {
        my $ok = false;
        if ((delete $row->{cbuser_id} == $self->user->userId
            or $self->user->may('admin') )
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
